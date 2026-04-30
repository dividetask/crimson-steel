require_relative '../lib/data_bootstrap'

# Run the data bootstrap before any spec loads. This copies any
# missing docs/<domain>/<file>.yaml.example into data/<file>.yaml
# so the spec suite starts from a known-good baseline without
# requiring a manual "cp" step. Existing data files are left
# untouched, so anything the dev has tweaked stays tweaked.
DataBootstrap.bootstrap!
