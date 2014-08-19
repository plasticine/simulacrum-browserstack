# encoding: UTF-8
require_relative './capybara_patch'
require_relative './tunnel'
require_relative './summary'
require_relative './api'
require_relative './driver'
require_relative './formatter'
require 'simulacrum/runner'
require 'parallel'
require 'yaml'
require 'retries'
require 'pry'

module Simulacrum
  module Browserstack
    # A Runner Class for Browserstack that handles creating a Browserstack
    # tunnel, closing it when done. Also handles running the suite in parallel.
    class Runner < Simulacrum::Runner
      # Exception to indicate that Browserstack has no available sessions
      # to start a new test run, this is used inside a retries loop but will
      # be raised if maximum retries is exceeded
      class NoRemoteSessionsAvailable < RuntimeError; end

      attr_reader :app_ports

      def initialize
        puts 'Simulacrum::Browserstack::Runner.initialize'
        @app_ports = app_ports
        @username = Simulacrum.runner_options.username
        @apikey = Simulacrum.runner_options.apikey
        @api = Simulacrum::Browserstack::API.new(@username, @apikey)
      end

      def run
        start_timer
        @tunnel = Simulacrum::Browserstack::Tunnel.new(@username, @apikey, @app_ports)
        puts 'Simulacrum::Browserstack::Runner.run'
        set_global_env
        run_in_parallel
        summarize_results
        @exit_code = summarize_exit_codes
      ensure
        @tunnel.close
      end

      def run_in_parallel
        puts 'Simulacrum::Browserstack::Runner.run_in_parallel'
        Simulacrum.logger.info('BrowserStack') { "Using runner with #{processes} remote workers" }
        @process_exit_codes, @process_results = Parallel.map_with_index(browsers, in_processes: processes) do |(browser_name, caps), index|
          begin
            ensure_available_remote_runner
            configure_app_port(index)
            configure_environment(browser_name, caps)
            configure_driver
            configure_rspec
            configure_browser_setting(browser_name)
            [run_rspec, { results: dump_results }]
          rescue SystemExit
            raise
            exit 1
          ensure
            quit_browser
          end
        end.transpose
      ensure
        stop_timer
      end

      private

      def quit_browser
        Capybara.current_session.driver.browser.quit
      end

      def configure_browser_setting(name)
        puts 'Simulacrum::Browserstack::Runner.configure_browser_setting'
        RSpec.configuration.around do |example|
          example.metadata[:browser] = name
          begin
            example.run
          end
        end
      end

      def configure_rspec
        super
        puts 'Simulacrum::Browserstack::Runner.configure_rspec'
        RSpec.configuration.instance_variable_set(:@reporter, reporter)
      end

      def configure_driver
        puts 'Simulacrum::Browserstack::Runner.configure_driver'
        Simulacrum::Browserstack::Driver.use
      end

      def reporter
        @reporter ||= RSpec::Core::Reporter.new(formatter)
      end

      def formatter
        @formatter ||= Simulacrum::Browserstack::Formatter.new($stdout)
      end

      def dump_results
        Marshal.dump(formatter.output_hash)
      end

      def ensure_available_remote_runner
        with_retries(max_tries: 10, base_sleep_seconds: 0.5, max_sleep_seconds: 15) do
          remote_worker_available?
        end
      end

      def remote_worker_available?
        account_details = @api.account_details
        unless account_details.sessions_running < account_details.sessions_allowed
          fail NoRemoteSessionsAvailable
        end
      end

      def start_timer
        @start_time = Time.now
      end

      def stop_timer
        @end_time = Time.now
      end

      def summarize_results
        summary = Simulacrum::Browserstack::Summary.new(@process_results, @start_time, @end_time)
        summary.dump_summary
        summary.dump_failures
        summary.dump_pending
      end

      def summarize_exit_codes
        (@process_exit_codes.reduce(&:+) == 0) ? 0 : 1
      end

      def configure_app_port(index)
        ENV['APP_SERVER_PORT'] = app_ports[index].to_s
      end

      # rubocop:disable MethodLength
      def configure_environment(name, caps)
        puts 'Simulacrum::Browserstack::Runner.configure_environment'
        ENV['BS_DRIVER_NAME']                 = name
        ENV['SELENIUM_BROWSER']               = caps['browser']
        ENV['SELENIUM_VERSION']               = caps['browser_version'].to_s
        ENV['BS_AUTOMATE_OS']                 = caps['os']
        ENV['BS_AUTOMATE_OS_VERSION']         = caps['os_version'].to_s
        ENV['BS_AUTOMATE_RESOLUTION']         = caps['resolution']
        ENV['BS_AUTOMATE_REQUIREWINDOWFOCUS'] = caps['requireWindowFocus'].to_s
        ENV['BS_AUTOMATE_PLATFORM']           = caps['platform']
        ENV['BS_AUTOMATE_DEVICE']             = caps['device']
        ENV['BS_AUTOMATE_DEVICEORIENTATION']  = caps['deviceOrientation']
        ENV['BS_BROWSERNAME']                 = caps['browserName']
        ENV['BS_REALMOBILE']                  = caps['realMobile'].to_s
      end
      # rubocop:enable MethodLength

      def processes
        Simulacrum.runner_options.max_processes || @api.account_details.sessions_allowed
      end

      def set_global_env
        ENV['SELENIUM_REMOTE_URL'] = @tunnel.selenium_remote_url
      end

      def app_ports
        @app_ports ||= begin
          if browsers.any?
            browsers.length.times.map { find_available_port }
          else
            [find_available_port]
          end
        end
      end

      def find_available_port
        server = TCPServer.new('127.0.0.1', 0)
        server.addr[1]
      ensure
        server.close if server
      end

      def browsers
        @browsers ||= begin
          if Simulacrum.config_file?
            browsers = Simulacrum.config_file['browsers']
            browsers = browsers.select do |name, value|
              name == Simulacrum.runner_options.browser
            end if Simulacrum.runner_options.browser
            browsers
          else
            # TODO: Raise a better error...
            fail 'DERP!'
          end
        end
      end
    end
  end
end
