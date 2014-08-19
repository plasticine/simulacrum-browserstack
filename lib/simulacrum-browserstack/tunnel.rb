# encoding: UTF-8
require 'timeout'
require 'fileutils'
require 'English'

module Simulacrum
  module Browserstack
    # Class for handling Browserstack tunnel opening/closing/management
    class Tunnel
      attr_reader :selenium_remote_url, :pid, :ports, :open
      alias_method :open?, :open

      DEFAULT_OPTIONS = {
        skip_check: true,
        only_automate: false,
        verbose: true,
        force: true,
        identifier: nil
      }

      def initialize(username, apikey, ports, options = {})
        @pid = nil
        @open = false
        @username = username
        @apikey = apikey
        @ports = ports
        @options = OpenStruct.new(DEFAULT_OPTIONS.clone.merge!(options))

        create_tunnel
        ensure_open
      end

      def selenium_remote_url
        "http://#{@username}:#{@apikey}@hub.browserstack.com/wd/hub"
      end

      def close
        Simulacrum.logger.debug('BrowserStack') { "Closing tunnel (pid #{@pid})" }
        kill
      end

      private

      def binary_path
        binary_path = `which BrowserStackLocal`.strip
        if $CHILD_STATUS.success? && File.executable?(binary_path)
          binary_path
        else
          Simulacrum.logger.fail('BrowserStack') { 'BrowserStackLocal binary not found or not executable' }
          exit(1)
        end
      end

      def create_tunnel
        @process = IO.popen(command)
        @pid = @process.pid
        Simulacrum.logger.debug('BrowserStack') { "Openning tunnel (pid #{@pid})" }
      end

      def command
        cmd = [binary_path]
        cmd << "-localIdentifier #{@options.identifier}" unless @options.identifier.nil?
        cmd << '-skipCheck'                              if @options.skip_check == true
        cmd << '-onlyAutomate'                           if @options.only_automate == true
        cmd << '-force'                                  if @options.force == true
        cmd << '-v'                                      if @options.verbose == true
        cmd << @apikey
        cmd << formatted_ports
        puts cmd.join(' ')
        cmd.join(' ')
      end

      def formatted_ports
        ports.map { |port| "localhost,#{port},0" }.join(',')
      end

      def kill
        Process.kill('TERM', @pid) if running?
      end

      def ensure_open
        Simulacrum.logger.debug('BrowserStack') { 'Waiting for tunnel to open' }
        Timeout.timeout(60) do
          sleep 1 until tunnel_connected?
        end
        @open = true
        Simulacrum.logger.debug('BrowserStack') { 'Tunnel open' }
      rescue Timeout::Error
        Simulacrum.logger.debug('BrowserStack') { 'Tunnel failed to open, exiting.' }
        exit(1)
      end

      def tunnel_connected?
        @process.gets =~ /^Connected.$/
      end

      def running?
        if @pid.nil?
          false
        else
          Process.getpgid(@pid)
          true
        end
      rescue Errno::ESRCH
        false
      end
    end
  end
end
