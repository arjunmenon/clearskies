# In-memory hash structure, persisted to disk via log file
#
# We usually don't flush to disk, since the data being stored can be
# regenerated.

class Permahash
  # Percent storage efficiency should reach before vacuuming
  DESIRED_EFFICIENCY = 0.25

  # Never vacuum if log has less than this many entries
  MINIMUM_VACUUM_SIZE = 4096

  HEADER = "CLEARSKIES PERMAHASH v1"

  def initialize path
    @path = path
    @hash = {}
    # FIXME Use locking to ensure that we don't open the logfile twice
    @logsize = 0
    read_from_file if File.exists? path
    @logfile = File.open @path, 'ab'
    @logfile.puts HEADER if @logsize == 0
    @logfile.flush
  end

  # Pass some operations through
  def size
    @hash.size
  end

  def each &bl
    @hash.each(&bl)
  end

  def [] key
    @hash[key]
  end

  def []= key, val
    @hash[key] = val
    save 'r', key, val
  end

  def delete key
    val = @hash.delete key
    save 'd', key, val
    val
  end

  def values
    @hash.values
  end

  def keys
    @hash.keys
  end

  def close
    @logfile.flush
    @logfile.close
    @logfile = nil
  end

  private
  # Save an update to disk
  def save oper, key, val=nil
    keyd = Marshal.dump key
    vald = Marshal.dump val
    @logfile.puts "#{oper}:#{keyd.size}:#{vald.size}"
    @logfile.write keyd
    @logfile.write vald
    @logsize += 1

    # Vacuum if log has gotten too large
    return unless @logsize > MINIMUM_VACUUM_SIZE
    return unless @logsize > @hash.size * 1.to_f / DESIRED_EFFICIENCY
    vacuum
  end

  def read_from_file
    File.open( @path, 'rb' ) do |f|
      first = f.gets
      raise "Invalid file header" unless first.chomp == HEADER

      bytes = first.size

      while !f.eof?
        command = f.gets
        # If the last line is a partial line, we discard it
        unless command =~ /\n\Z/
          discard_until bytes
          return
        end

        oper, keysize, valsize = command.split ':'
        keysize = keysize.to_i
        valsize = valsize.to_i

        keyd = f.read keysize
        vald = f.read valsize

        if !keyd || !vald
          discard_until bytes
          return
        end

        if keyd.size != keysize || vald.size != valsize
          discard_until bytes
          return
        end

        bytes += command.size
        bytes += keysize
        bytes += valsize

        key = Marshal.load keyd
        val = Marshal.load vald
        @logsize += 1
        case oper
        when 'r' # replace
          @hash[key] = val
        when 'd' # delete
          @hash.delete key
        end
      end
    end
  end

  def discard_until bytes
    warn "Incomplete database: #@path, truncating to #{bytes} bytes" if $DEBUG
    File.truncate @path, bytes
  end

  def vacuum
    warn "Vacuuming #{@path.inspect}, has #@logsize entries, only needs #{@hash.size}" if $DEBUG
    temp = @path + ".#$$.tmp"
    @logfile = File.open temp, 'wb'
    @logsize = 0
    @logfile.puts HEADER
    @hash.each do |key,val|
      save 'r', key, val
    end
    @logfile.close
    File.rename temp, @path
    @logfile = File.open @path, 'ab'
  end
end