module SidekiqRunner
  class SidekiqInstance
    RUNNER_ATTRIBUTES = [:bundle_env, :chdir, :requirefile]
    RUNNER_ATTRIBUTES.each { |att| attr_accessor att }

    CONFIG_FILE_ATTRIBUTES = [:concurrency, :verbose, :pidfile, :logfile, :tag, :rbtrace, :uid, :gid]
    CONFIG_FILE_ATTRIBUTES.each { |att| attr_accessor att }

    attr_reader :name, :queues, :config_blocks

    def initialize(name)
      raise "No sidekiq instance name given!" if name.empty?

      @name = name
      @queues = []

      @bundle_env   = true
      @chdir        = nil
      @requirefile  = nil
      @pidfile      = File.join(Dir.pwd, 'tmp', 'pids', "#{@name}.pid")
      @logfile      = File.join(Dir.pwd, 'log', "#{@name}.log")
      @concurrency  = 4
      @verbose      = false
      @tag          = name
      @rbtrace      = false
      @uid          = nil
      @gid          = nil
      @config_blocks = []
    end

    def add_queue(queue_name, weight = 1)
      raise "Cannot add the queue. The name is empty!" if queue_name.empty?
      raise "Cannot add the queue. The weight is not an integer!" unless weight.is_a? Integer
      raise "Cannot add the queue. The queue with \"#{queue_name}\" name already exist" if @queues.any? { |q| q.first == queue_name }

      @queues << [queue_name, weight]
    end

    def god_config(&block)
      @config_blocks << block
    end

    def merge_config_file!(yml)
      # Get global configuration options.
      SidekiqInstance::CONFIG_FILE_ATTRIBUTES.each do |k|
        send("#{k}=", yml[k]) unless yml[k].nil?
      end

      # Override with instance-specific options.
      if (syml = yml[@name.to_sym]) && syml.is_a?(Hash)
        syml = Hash[syml.map { |k, v| [k.to_sym, v] }]

        SidekiqInstance::CONFIG_FILE_ATTRIBUTES.each do |k|
          send("#{k}=", syml[k]) unless syml[k].nil?
        end
      end
    end

    def sane?
      raise "No queues given for #{@name}!" if @queues.empty?
      raise "No requirefile given for #{@name} and not in Rails environment!" if !defined?(Rails) && !requirefile
    end

    def build_start_command
      create_directories!

      cmd = []
      cmd << 'bundle exec' if bundle_env
      cmd << (rbtrace ? File.expand_path('../../script/sidekiq_rbtrace', __dir__) : 'sidekiq')
      cmd << "-c #{concurrency}"
      cmd << '-v' if verbose
      cmd << "-P #{pidfile}"
      cmd << "-e #{Rails.env}" if defined?(Rails)
      cmd << "-r #{requirefile}" if requirefile
      cmd << "-g '#{tag}'"

      queues.each do |q, w|
        cmd << "-q #{q},#{w}"
      end

      cmd.join(' ')
    end

    private

    def create_directories!
      FileUtils.mkdir_p(File.dirname(logfile))
      FileUtils.mkdir_p(File.dirname(pidfile))
    end
  end
end
