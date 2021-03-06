# coding: utf-8
# Simple file watcher. Detect changes in files and directories.
#
# Issues: Currently doesn't monitor changes in directorynames
class FileWatcher

  attr_accessor :filenames

  def self.VERSION
    return '0.5.3'
  end

  def update_spinner(label)
    return nil unless @show_spinner
    @spinner ||= %w(\\ | / -)
    print "#{' ' * 30}\r#{label}  #{@spinner.rotate!.first}\r"
  end

  def initialize(unexpanded_filenames, *args)
    if(args.first)
      options = args.first
    else
      options = {}
    end
    @unexpanded_filenames = unexpanded_filenames
    @unexpanded_excluded_filenames = options[:exclude]
    @filenames = nil
    @stored_update = nil
    @keep_watching = false
    @pausing = false
    @last_snapshot = mtime_snapshot
    @end_snapshot = nil
    @dontwait = options[:dontwait]
    @show_spinner = options[:spinner]
    @interval = options[:interval]
  end

  def watch(sleep=0.5, &on_update)
    trap("SIGINT") {return }
    @sleep = sleep
    if(@interval and @interval > 0)
      @sleep = @interval
    end
    @stored_update = on_update
    @keep_watching = true
    if(@dontwait)
      yield '',''
    end
    while @keep_watching
      @end_snapshot = mtime_snapshot if @pausing
      while @keep_watching && @pausing
        update_spinner('Pausing')
        Kernel.sleep @sleep
      end
      while @keep_watching && !filesystem_updated? && !@pausing
        update_spinner('Watching')
        Kernel.sleep @sleep
      end
      # test and null @updated_file to prevent yielding the last
      # file twice if @keep_watching has just been set to false
      yield @updated_file, @event if @updated_file
      @updated_file = nil
    end
    @end_snapshot = mtime_snapshot
    finalize(&on_update)
  end

  def pause
    @pausing = true
    update_spinner('Initiating pause')
    Kernel.sleep @sleep # Ensure we wait long enough to enter pause loop
                        # in #watch
  end

  def resume
    if !@keep_watching || !@pausing
      raise "Can't resume unless #watch and #pause were first called"
    end
    @last_snapshot = mtime_snapshot  # resume with fresh snapshot
    @pausing = false
    update_spinner('Resuming')
    Kernel.sleep @sleep # Wait long enough to exit pause loop in #watch
  end

  # Ends the watch, allowing any remaining changes to be finalized.
  # Used mainly in multi-threaded situations.
  def stop
    @keep_watching = false
    update_spinner('Stopping')
    return nil
  end

  # Calls the update block repeatedly until all changes in the
  # current snapshot are dealt with
  def finalize(&on_update)
    on_update = @stored_update if !block_given?
    snapshot = @end_snapshot ? @end_snapshot : mtime_snapshot
    while filesystem_updated?(snapshot)
      update_spinner('Finalizing')
      on_update.call(@updated_file, @event)
    end
    @end_snapshot =nil
    return nil
  end

  # Takes a snapshot of the current status of watched files.
  # (Allows avoidance of potential race condition during #finalize)
  def mtime_snapshot
    snapshot = {}
    @filenames = expand_directories(@unexpanded_filenames)

    if(@unexpanded_excluded_filenames != nil and @unexpanded_excluded_filenames.size > 0)
      # Remove files in the exclude filenames list
      @filtered_filenames = []
      @excluded_filenames = expand_directories(@unexpanded_excluded_filenames)
      @filenames.each do |filename|
        if(not(@excluded_filenames.include?(filename)))
          @filtered_filenames << filename
        end
      end
      @filenames = @filtered_filenames
    end

    @filenames.each do |filename|
      mtime = File.exist?(filename) ? File.stat(filename).mtime : Time.new(0)
      snapshot[filename] = mtime
    end
    return snapshot
  end

  def filesystem_updated?(snapshot_to_use = nil)
    snapshot = snapshot_to_use ? snapshot_to_use : mtime_snapshot
    forward_changes = snapshot.to_a - @last_snapshot.to_a

    forward_changes.each do |file,mtime|
      @updated_file = file
      unless @last_snapshot.fetch(@updated_file,false)
        @last_snapshot[file] = mtime
        @event = :new
        return true
      else
        @last_snapshot[file] = mtime
        @event = :changed
        return true
      end
    end

    backward_changes = @last_snapshot.to_a - snapshot.to_a
    forward_names = forward_changes.map{|change| change.first}
    backward_changes.reject!{|f,m| forward_names.include?(f)}
    backward_changes.each do |file,mtime|
      @updated_file = file
      @last_snapshot.delete(file)
      @event = :delete
      return true
    end
    return false
  end

  def last_found_filenames
    @last_snapshot.keys
  end

  def expand_directories(patterns)
    if(!patterns.kind_of?Array)
      patterns = [patterns]
    end
    patterns.map { |it| Dir[fulldepth(expand_path(it))] }.flatten.uniq
  end

  private

  def fulldepth(pattern)
    if File.directory? pattern
      "#{pattern}/**/*"
    else
      pattern
    end
  end

  def expand_path(pattern)
    if pattern.start_with?('~')
      File.expand_path(pattern)
    else
      pattern
    end
  end

end
