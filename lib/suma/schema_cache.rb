module Suma
  class SchemaCache
    CACHE_DIR = ".cache/schema".freeze

    def cache_get(key)
      path = cache_path(key)
      return nil unless File.exist?(path)

      File.open(path, "rb") { |f| Marshal.load(f) }
    rescue
      nil
    end

    def cache_put(key, value)
      FileUtils.mkdir_p(CACHE_DIR)
      path = cache_path(key)

      File.open(path, "wb") { |f| Marshal.dump(value, f) }
    end

    def cache_path(key)
      File.join(CACHE_DIR, key)
    end
  end
end
