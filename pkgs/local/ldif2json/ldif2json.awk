
# Convert LDIF into JSON

# MIT License
# Copyright (c) 2017 Christopher Harrison

function json_string(str) {
  # Convert backslashes to double-backslashes
  str = gensub("\\\\", "\\\\\\\\", "g", str)
  # Replace litteral newlines with '^M'
  str = gensub("\r", "^M", "g", str)
  # Convert a string into an escaped JSON string, with enclosing quotes
  return "\"" gensub(/"/, "\\\\\"", "g", str) "\""
}

BEGIN {
  FS = "::? "
  ORS = ""

  in_dn = 0
  first_dn = 0

  # Array of results
  print "["
}

/^#/ || $1 == "version" || $1 == "search" || $1 == "result" {
  # Skip comments, version and ldapsearch result entities
  next
}

$1 == "dn" {
  # We've found an entity
  if (first_dn) print ","
  print "{"

  in_dn = 1
  first_dn = 1

  # Reset attributes
  delete attributes
}

in_dn {
  if (NF == 2) {
    # New attribute
    last_attr = $1
    attr_index = 1
    if (last_attr in attributes) attr_index = length(attributes[last_attr]) + 1
    value = $2

  } else {
    # Continuation of previous attribute
    attr_index = length(attributes[last_attr])
    value = attributes[last_attr][attr_index] gensub(/^ /, "", 1)
  }

  attributes[last_attr][attr_index] = value
}

in_dn && /^$/ {
  # Write attributes
  first_attr = 0
  for (attr in attributes) {
    if (first_attr) print ","
    print json_string(attr) ":"
    first_attr = 1

    if (length(attributes[attr]) == 1) {
      # Scalar attribute
      print json_string(attributes[attr][1])

    } else {
      # Array attribute
      print "["

      first_arr = 0
      for (i in attributes[attr]) {
        if (first_arr) print ","
        print json_string(attributes[attr][i])
        first_arr = 1
      }

      print "]"
    }
  }

  # End of entity
  print "}"
  in_dn = 0
}

END {
  # End of array
  print "]"
}
