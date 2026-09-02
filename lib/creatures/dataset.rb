require 'yaml'
require 'fileutils'
require_relative 'record'
require_relative '../data_paths'

module Creatures
  # Loads + indexes every `creatures_data_*.{yaml,json}` file. For each
  # logical data file the loader prefers a writable copy under `data/`
  # over the read-only `docs/common/creatures/` example (mirroring the
  # Equipment / Encounter / Chronicle overlay pattern). Each file's
  # `characters` list is validated and normalized through
  # Creatures::Record; the merged set is keyed by integer id.
  #
  # Mutations (Spawn Creature From Template, Delete Creature) are written
  # straight back to `data/<source-file>` so spawned Creatures survive a
  # restart instead of living only in memory.
  module Dataset
    EXAMPLE_DIR  = File.expand_path('../../docs/common/creatures', __dir__)
    DEFAULT_DATA_DIR = DataPaths.dir
    PATTERN      = 'creatures_data_*.{yaml,yml,json}'.freeze

    module_function

    # The writable overlay directory. Overridable (e.g. tests point it at
    # a tmpdir) so persistence never touches the live `data/` dir.
    def data_dir
      @data_dir ||= DataPaths.dir
    end

    def data_dir=(dir)
      @data_dir = dir
    end

    # Returns the loaded dataset hash: { id (Integer) => record }.
    def all
      load! unless defined?(@records) && @records
      @records
    end

    def get(id)
      all[Integer(id)]
    end

    def ids_in_load_order
      load! unless defined?(@order) && @order
      @order
    end

    # A record's `:source` is the writable overlay basename (no
    # `.example`), e.g. `creatures_data_enemies.yaml`. The example file
    # `creatures_data_enemies.example.yaml` maps onto that same key, so a
    # `data/` copy transparently overrides the shipped example.
    def overlay_name(basename)
      basename.sub(/\.example(\.[^.]+)\z/, '\1')
    end

    # The logical source basenames (overlay form). Union of the data dir
    # (already overlay-named) and the example dir (mapped to overlay form).
    # An isolated Campaign (DataPaths) contributes only its own files, so
    # no example roster loads behind it.
    def source_files
      names = {}
      Dir.glob(File.join(data_dir, PATTERN)).each { |p| names[File.basename(p)] = true }
      if DataPaths.example_fallback?
        Dir.glob(File.join(EXAMPLE_DIR, PATTERN)).each { |p| names[overlay_name(File.basename(p))] = true }
      end
      names.keys.sort
    end

    # The path a given source is loaded from: the `data/` overlay when
    # present, otherwise the read-only `.example` file in the docs dir.
    # Returns nil when an isolated Campaign has no file of that name.
    def load_path_for(basename)
      overlay = File.join(data_dir, basename)
      return overlay if File.exist?(overlay)
      return nil unless DataPaths.example_fallback?
      ext = File.extname(basename)
      example = File.join(EXAMPLE_DIR, "#{File.basename(basename, ext)}.example#{ext}")
      File.exist?(example) ? example : File.join(EXAMPLE_DIR, basename)
    end

    # The path mutations are written to — always the `data/` overlay.
    def data_path_for(basename)
      File.join(data_dir, basename)
    end

    def load!
      @records = {}
      @order   = []
      source_files.each do |basename|
        path = load_path_for(basename)
        next unless path && File.exist?(path)
        data = YAML.safe_load_file(path) || {}
        (data['characters'] || []).each do |raw|
          rec = Creatures::Record.normalize(raw, source: basename)
          if @records.key?(rec[:id])
            raise ArgumentError, "Creature id #{rec[:id]} appears in multiple " \
                                 "creatures_data_* files (second sighting in #{basename})"
          end
          rec[:source] = basename
          @records[rec[:id]] = rec
          @order << rec[:id]
        end
      end
      self
    end

    def reset!
      @records = nil
      @order = nil
      @data_dir = nil
    end

    # Used by Spawn Creature From Template. Allocates a fresh id one past
    # the current maximum across the dataset.
    def next_id
      load! unless defined?(@records) && @records
      max = @records.keys.max || 0
      max + 1
    end

    # Insert a record and persist its source file. A record's `:source`
    # routes it to a `data/<source-file>`; records with no source (should
    # not happen for spawns, which inherit the template's source) fall
    # back to a default enemies overlay.
    def insert!(record)
      load! unless defined?(@records) && @records
      raise ArgumentError, "Creature id #{record[:id]} already exists" \
        if @records.key?(record[:id])
      record[:source] ||= 'creatures_data_enemies.yaml'
      @records[record[:id]] = record
      @order << record[:id]
      persist_source!(record[:source])
      record
    end

    def delete!(id)
      i = Integer(id)
      load! unless defined?(@records) && @records
      rec = @records[i]
      return false unless rec
      @records.delete(i)
      @order.delete(i)
      persist_source!(rec[:source]) if rec[:source]
      true
    end

    # Write every in-memory record whose `:source` is `basename` back to
    # that file's `data/` overlay, atomically. Records keep their load
    # order within the file.
    def persist_source!(basename)
      return if basename.nil?
      characters = @order
                   .map { |id| @records[id] }
                   .select { |r| r && r[:source] == basename }
                   .map { |r| Creatures::Record.serialize(r) }
      out  = { 'characters' => characters }
      path = data_path_for(basename)
      FileUtils.mkdir_p(File.dirname(path))
      tmp = "#{path}.tmp"
      File.write(tmp, YAML.dump(out))
      File.rename(tmp, path)
    end
  end
end
