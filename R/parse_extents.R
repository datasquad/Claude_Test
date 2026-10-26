# Parses the extent wording of a 30mph exception ("from a point 155 metres
# west of its junction with Pentre Tai Road for a distance of 605 metres
# east") into the fields build_segment() uses, and flags what it could not
# parse so it can be completed by hand. Used by the
# exception-segments-template chunk of WalesSpeedLimit.qmd.

library(tidyverse)

dist_re <- "(\\d[\\d,]*(?:\\.\\d+)?)\\s?(?:metres|metre|meters|m)\\b"
dir_re  <- "((?:north|south)?[- ]?(?:north|south|east|west)(?:erly|wards|ward)?)"
about_re <- "(?:approximately |approx\\.? ?)?"
jct_re  <- "(?:the (?:centre(?: point)?|southern tangent point|western side|eastern side) of )?(?:its|the) (?:roundabout |westerly |easterly |northern |southern )?junction (?:with|to) "
# A cross road, possibly given as "the B4265, St Brides Road". Lower-case
# "the" only: "The Firs" is a street name.
ref_re  <- "(?-i:the )?((?:[^,;]*?\\b[AB]\\d{1,4}, )?[^,;]+?)(?=\\s+(?:for|to|in an?|and contiguous|including|up to)\\b|,|;|\\.\\s|\\.$|$)"
# A point given relative to the existing speed limit rather than a junction.
limit_re <- "(?:the (?:current |existing )?\\d+mph (?:speed )?limit (?:at |on [^,]+? )?)?"
landmark_re <- regex(
  "boundary|propert|\\blimit\\b|signs?\\b|school|fuel|playground|public house|\\bchurch\\b(?! (?:street|road|close|lane|meadow))|car sales|cattle grid|end of|(?-i:access road)|closed end|stub end|tangent|circumference|known as",
  ignore_case = TRUE
)
# Road names that are safe to treat as junctions in an informal "from X to Y".
road_suffix_re <- "(?:Road|Way|Street|Lane|Drive|Avenue|Close|Hill|Place|Crescent|Court|Parkway|Row|Gardens|Terrace|View|[Rr]oundabout)$"

# "Two Locks Road roundabout" is the junction with Two Locks Road; a
# roundabout with its own name ("Rougemont roundabout") is kept as it is.
roundabout_to_road <- function(x) {
  road <- str_remove(x, "\\s+[Rr]oundabout$")
  if_else(str_detect(road, "(?:Road|Way|Street|Lane|Drive|Avenue)$"), road, x)
}

# "south-westwards" / "north westerly" / "easterly" -> "south_west" / "north_west" / "east"
norm_dir <- function(x) {
  x <- str_to_lower(str_trim(x)) |>
    str_remove("(erly|wards|ward)$") |>
    str_replace("^(north|south)[- ]?(east|west)$", "\\1_\\2")
  if_else(x %in% c("north", "south", "east", "west", "north_east", "north_west",
                   "south_east", "south_west"), x, NA_character_)
}

# A lower-case compass word after a cross road ("Fulmer Road south for ...");
# road names are capitalised, so "Port Road West" is left alone.
trailing_dir_re <- "\\s+((?:north|south)?[- ]?(?:north|south|east|west)(?:erly|wards)?)(?:\\s+then\\s+.*)?$"
trailing_dir <- function(x) str_match(x, trailing_dir_re)[, 2]

# Cross road as named in OS Open Roads: drop "the", brackets, a road number
# given before its name ("B4265, St Brides Road"), a second road ("Old Hill
# and Christchurch Road") and a trailing place ("Oaklands Road in
# Pontlliw"); keep the name of a numbered road ("U1723 Farrington Lane" ->
# "Farrington Lane"), or the number of an A/B road given by number only.
clean_ref <- function(x) {
  x |>
    str_remove("^the ") |>
    str_remove("^.*?\\b[AB]\\d{1,4},\\s+") |>
    str_remove_all("\\s*\\([^)]*\\)") |>
    str_remove("\\s+known as\\s.*$") |>
    str_remove(trailing_dir_re) |>
    str_remove("\\s+(?i)and\\s.*$") |>
    str_remove("\\s+in\\s+[A-Z][\\w-]+$") |>
    str_remove("^[ABCU]\\d+\\s+(?=[A-Z])") |>
    str_squish()
}

# Parses one section's wording. Returns a one-row tibble.
parse_extent <- function(text) {
  out <- tibble(from_road = NA_character_, from_offset_m = NA_real_, from_offset_dir = NA_character_,
                to_road = NA_character_, to_offset_m = NA_real_, to_offset_dir = NA_character_,
                length_m = NA_real_, direction = NA_character_, parsed = FALSE)
  if (is.na(text)) return(out)
  # Newport-style entries repeat the road name before ", from ...", and the
  # Vale's Order adds "contiguous with the existing 40mph speed restriction".
  s <- text |>
    str_remove("^[^,]*?,\\s+(?=(?i)from\\b)") |>
    # Press wording: "Ocean Way will change from ...", "... will also revert to 30mph between ..."
    str_remove("^[A-Z][^,]*? will (?:also )?(?:change|revert to 30mph|apply to)\\s+") |>
    # Caerphilly: "Coed y Brain Road from Coed-y-Brain roundabout ..."
    str_remove("^(?!(?i)from\\b)[^,]*?\\s+(?=(?i)(?:from|between)\\b)") |>
    str_replace("^(?i)from the roundabout at the junction", "from its junction") |>
    str_remove_all(regex(",?\\s*(?:and |to be )?contiguous with (?:the )?(?:existing )?\\S+ (?:speed )?(?:restriction|limit)",
                         ignore_case = TRUE)) |>
    str_squish()
  num <- \(x) as.numeric(str_remove_all(x, ","))
  i <- \(p) regex(p, ignore_case = TRUE)

  # --- start of the section
  m_pt  <- str_match(s, i(paste0("^from ", limit_re, "(?:a point )?", about_re,
                                  dist_re, "(?: in)? (?:an? )?(?:general(?:ly)? )?", dir_re,
                                  "(?: direction)? (?:of|from) (?:", jct_re, ")?", ref_re)))
  m_jct <- str_match(s, i(paste0("^from ", jct_re, ref_re)))
  # "from Henllys Way roundabout for approximately 486m ..."
  m_plain <- str_match(s, i(paste0("^from (?:its (?:intersection|junction) with )?", ref_re, "(?=\\s+for\\b)")))
  if (is.na(m_jct[1]) && !is.na(m_plain[1])) m_jct <- m_plain
  if (!is.na(m_pt[1])) {
    out$from_offset_m <- num(m_pt[2]); out$from_offset_dir <- norm_dir(m_pt[3])
    out$from_road <- roundabout_to_road(clean_ref(m_pt[4])); rest <- str_sub(s, nchar(m_pt[1]) + 1)
    dir_after_ref <- trailing_dir(m_pt[4])
  } else if (!is.na(m_jct[1])) {
    out$from_road <- roundabout_to_road(clean_ref(m_jct[2])); rest <- str_sub(s, nchar(m_jct[1]) + 1)
    dir_after_ref <- trailing_dir(m_jct[2])
  } else {
    # Informal "from Newport Road to Cwmbran Drive" / "between X and Y":
    # usable only when both ends are plainly road names.
    m_ft <- str_match(s, i("^(?:from|between) (?:its (?:intersection|junction) with )?(?:the )?(.+?) (?:to|and) (?:its junction with )?(?:the )?([^,]+?)(?:,.*)?$"))
    ends <- roundabout_to_road(clean_ref(m_ft[2:3]))
    if (!is.na(m_ft[1]) && all(str_detect(ends, road_suffix_re)) && !any(str_detect(ends, "[,\\d]")) &&
        all(str_detect(ends, "^[A-Z]")) && all(str_count(ends, "\\S+") >= 2)) {
      out$from_road <- ends[1]; out$to_road <- ends[2]; out$parsed <- TRUE
    }
    return(out)
  }

  # --- end of the section
  m_topt <- str_match(rest, i(paste0("\\bto ", limit_re, "(?:a point )?(?:on [^,]+? )?", about_re, dist_re,
                                     "(?: in)? (?:an? )?(?:general(?:ly)? )?(?:", dir_re, "(?: direction)? )?",
                                     "(?:of|from) (?:the centre(?: point)? of )?",
                                     "(?:(its|that|said|this|the) (?:\\w+ )?junction(?: (?:with|to) )?)?",
                                     "(?:", ref_re, ")?(?: in an? ", dir_re, " direction)?")))
  m_tojct <- str_match(rest, i(paste0("\\bto ", jct_re, ref_re)))
  # "... to Rover Way": only a plain road name counts.
  m_toroad <- str_match(rest, paste0("^\\s+to (?:the )?([A-Z][^,]*?", road_suffix_re, ")"))
  # "for 190 metres in a northerly direction and for 109 metres in a
  # southerly direction": both sides of the junction.
  m_two <- str_match(rest, i(paste0("\\bfor (?:a distance of )?", dist_re, " in an? ", dir_re, " direction and for ",
                                    dist_re, " in an? ", dir_re, " direction")))
  m_len <- str_match(rest, i(paste0("\\bfor (?:a distance of )?", about_re, dist_re,
                                    "(?:,? (?:in an? )?(?:general(?:ly)? )?", dir_re, "(?: direction)?)?")))
  # Direction stated before "for", in lower case ("southwards for", "in a
  # generally southerly direction for"); the first if it then changes.
  m_dir_before <- str_match(rest, paste0("(?:in an? )?(?:general(?:ly)? )?", dir_re,
                                         "(?: and then [a-z -]+?)?(?: directions?)?,?\\s+for\\b"))
  entire <- str_detect(rest, i("entire length"))

  if (!is.na(m_two[1])) {
    out$from_offset_m <- num(m_two[4]); out$from_offset_dir <- norm_dir(m_two[5])
    out$to_road <- out$from_road
    out$to_offset_m <- num(m_two[2]); out$to_offset_dir <- norm_dir(m_two[3])
  } else if (!is.na(m_topt[1])) {
    out$to_offset_m <- num(m_topt[2])
    out$to_offset_dir <- norm_dir(coalesce(m_topt[3], m_topt[6]))
    out$to_road <- if (str_to_lower(coalesce(m_topt[4], "")) %in% c("that", "said", "this") || is.na(m_topt[5])) {
      out$from_road
    } else {
      clean_ref(m_topt[5])
    }
  } else if (!is.na(m_tojct[1])) {
    out$to_road <- roundabout_to_road(clean_ref(m_tojct[2]))
  } else if (!is.na(m_toroad[1])) {
    out$to_road <- roundabout_to_road(clean_ref(m_toroad[2]))
  } else if (!is.na(m_len[1])) {
    out$length_m <- num(m_len[2])
    out$direction <- norm_dir(coalesce(m_len[3], m_dir_before[2], dir_after_ref))
  } else if (entire) {
    # From a junction to the end of the road: the whole road.
    out$from_road <- NA_character_; out$from_offset_m <- NA_real_; out$from_offset_dir <- NA_character_
  } else {
    return(out)
  }
  out$parsed <- TRUE
  out
}

# Reasons a segment needs work by hand ("" when it can be cut automatically).
flag_extent <- function(seg) {
  with(seg, {
    reason <- character()
    has_extent <- !is.na(extent_text)
    if (extent_detail %in% c("none", "vague")) {
      reason <- "no usable extent in source: get the TRO schedule or map"
    } else if (extent_detail == "approximate" && !(parsed && !is.na(from_road) && !is.na(to_road))) {
      reason <- "extent given by landmarks, not measured points: digitise by hand"
    } else if (extent_detail == "whole_road" && is.na(from_road)) {
      if (is.na(road_base) && is.na(road_number)) reason <- c(reason, "road has no name: identify it by hand")
      if (str_detect(coalesce(road_base, ""), regex("roundabout|interchange|\\bat\\b", ignore_case = TRUE)))
        reason <- c(reason, "named roundabout or descriptive name: check it exists in OS Open Roads")
    } else if (!parsed) {
      reason <- "extent not parsed: fill the fields by hand"
    } else {
      if (extent_detail == "approximate")
        reason <- "informal from/to wording: check the cut against the source"
      refs <- c(from_road, to_road)
      # Ignore the boilerplate "contiguous with the existing 40mph speed limit".
      wording <- str_remove_all(extent_text, regex("contiguous with[^,|]*|the (?:current |existing )?\\d+mph (?:speed )?limit", ignore_case = TRUE))
      if (any(str_detect(refs, landmark_re), na.rm = TRUE) || (has_extent && str_detect(wording, landmark_re)))
        reason <- c(reason, "starts or ends at a landmark (property, limit, sign): check by hand")
      if (any(str_detect(refs, "^[CU]\\d+$"), na.rm = TRUE))
        reason <- c(reason, "junction road given only by a C/U number: add its name")
      if (any(str_detect(refs, regex("un-?named", ignore_case = TRUE)), na.rm = TRUE))
        reason <- c(reason, "junction road is unnamed: identify it by hand")
      if (!is.na(road_base) && any(refs %in% road_base))
        reason <- c(reason, "junction road has the road's own name: check which junction is meant")
      if (str_detect(coalesce(road_base, ""), "/"))
        reason <- c(reason, "section spans two road names: digitise by hand")
      if (any(str_detect(refs, regex("roundabout|interchange", ignore_case = TRUE)), na.rm = TRUE))
        reason <- c(reason, "junction is a named roundabout: check the name exists in OS Open Roads")
      if (!is.na(length_m) && is.na(direction))
        reason <- c(reason, "direction not stated: cut only if one direction fits the road")
      if ((!is.na(from_offset_m) && is.na(from_offset_dir)) || (!is.na(to_offset_m) && is.na(to_offset_dir)))
        reason <- c(reason, "offset direction not stated")
      if (is.na(road_base) && is.na(road_number)) reason <- c(reason, "road has no name: identify it by hand")
    }
    paste(reason, collapse = "; ")
  })
}
