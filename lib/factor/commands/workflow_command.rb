# encoding: UTF-8

require 'factor/commands/base'
require 'factor/workflow/runtime'

module Factor
  module Commands
    # Workflow is a Command to start the factor runtime from the CLI
    class WorkflowCommand < Factor::Commands::Command
      def initialize
        @workflows = {}
        super
      end

      def server(_args, options)
        config_settings = {}
        config_settings[:credentials] = options.credentials
        workflow_filename = File.expand_path(options.path || '.')
        @destination_stream = File.new(options.log, 'w+') if options.log

        load_config(config_settings)
        load_all_workflows(workflow_filename)
        block_until_interupt
        logger.info 'Good bye!'
      end

      def cloud(args, options)
        account_id, workflow_id, api_key = args
        host        = (options.host || "https://factor.io").sub(/(\/)+$/,'')

        if !api_key || !workflow_id || !account_id
          logger.error "API Key, Worklfow ID and Acount ID are all required"
          exit
        end

        logger.info "Getting workflow (#{workflow_id}) from Factor.io Cloud"
        begin
          workflow_url = "#{host}/#{account_id}/workflows/#{workflow_id}.json?auth_token=#{api_key}"
          raw_content = RestClient.get(workflow_url)
          workflow_info = JSON.parse(raw_content)
        rescue => ex
          logger.error "Couldn't retreive workflow: #{ex.message}"
          exit
        end

        workflow_definition = workflow_info["definition"]

        logger.info "Getting credentials from Factor.io Cloud"
        begin
          credential_url = "#{host}/#{account_id}/credentials.json?auth_token=#{api_key}"
          raw_content = RestClient.get(credential_url)
          credentials = JSON.parse(raw_content)
        rescue => ex
          logger.error "Couldn't retreive workflow: #{ex.message}"
          exit
        end

        configatron[:credentials].configure_from_hash(credentials)

        @workflows[workflow_id] = load_workflow_from_definition(workflow_definition)

        block_until_interupt

        logger.info 'Good bye!'
      end

      private

      def load_all_workflows(workflow_filename)
        glob_ending = workflow_filename[-1] == '/' ? '' : '/'
        glob = "#{workflow_filename}#{glob_ending}*.rb"
        file_list = Dir.glob(glob)
        if !file_list.all? { |file| File.file?(file) }
          logger.error "#{workflow_filename} is neither a file or directory"
        elsif file_list.count == 0
          logger.error 'No workflows in this directory to run'
        else
          file_list.each { |filename| load_workflow(File.expand_path(filename)) }
        end
      end

      def block_until_interupt
        logger.info 'Ctrl-c to exit'
        begin
          loop do
            sleep 1
          end
        rescue Interrupt
          logger.info 'Exiting app...'
        end
      end

      def load_workflow(workflow_filename)
        # workflow_filename = File.expand_path(filename)
        logger.info "Loading workflow from #{workflow_filename}"
        begin
          workflow_definition = File.read(workflow_filename)
        rescue => ex
          logger.error "Couldn't read file #{workflow_filename}", exception:ex
          return
        end

        @workflows[workflow_filename] = load_workflow_from_definition(workflow_definition, File.basename(workflow_filename))
      end

      def load_workflow_from_definition(workflow_definition, filename)
        logger.info "Setting up workflow processor"
        begin
          credential_settings = configatron.credentials.to_hash
          runtime = Factor::Workflow::Runtime.new(credential_settings, logger: logger, workflow_filename: filename)
        rescue => ex
          message = "Couldn't setup workflow process"
          logger.error message:message, exception:ex
        end

        workflow_thread = fork do
          begin
            logger.info "Starting workflow"
            runtime.load(workflow_definition)
          rescue => ex
            logger.error message: "Couldn't start workflow", exception: ex
          end
        end

        workflow_thread
      end

    end
  end
end
