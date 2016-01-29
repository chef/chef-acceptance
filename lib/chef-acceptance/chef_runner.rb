require 'chef-acceptance/executable_helper'
require 'mixlib/shellout'
require 'json'
require 'bundler'
require 'chef-acceptance/acceptance_cookbook'

module ChefAcceptance

  # Responsible for generating a CCR shellout and running it
  class ChefRunner
    attr_reader :acceptance_cookbook
    attr_reader :test_suite
    attr_reader :recipe
    attr_reader :duration

    def initialize(test_suite, recipe)
      @test_suite = test_suite
      @acceptance_cookbook = test_suite.acceptance_cookbook
      @recipe = recipe
      @duration = 0
    end

    def run!
      # prep and create chef attribute and config file
      prepare_required_files

      chef_shellout = build_shellout(
        cwd: acceptance_cookbook.root_dir,
        chef_config_file: chef_config_file,
        dna_json_file: dna_json_file,
        recipe: "#{AcceptanceCookbook::ACCEPTANCE_COOKBOOK_NAME}::#{recipe}"
      )

      Bundler.with_clean_env do
        chef_shellout.run_command
        # execution_time can return nil and we always want to return a number
        # for duration().
        @duration = chef_shellout.execution_time || 0
        chef_shellout.error! # This will only raise an error if there was one
      end
    end

    private

    def dna
      {
        'chef-acceptance' => {
          'suite-dir' => File.expand_path(test_suite.name)
        }
      }
    end

    def chef_config_template
      <<-EOS.gsub(/^\s+/, "")
        cookbook_path '#{File.expand_path(File.join(acceptance_cookbook.root_dir, '..'))}'
        node_path '#{File.expand_path(File.join(acceptance_cookbook.root_dir, 'nodes'))}'
        stream_execute_output true
      EOS
    end

    def prepare_required_files
      FileUtils.rmtree temp_dir
      FileUtils.mkpath temp_dir
      File.write(dna_json_file, JSON.pretty_generate(dna))

      FileUtils.mkpath chef_dir
      File.write(chef_config_file, chef_config_template)
    end

    def build_shellout(options = {})
      cwd = options.fetch(:cwd, Dir.pwd)
      recipe = options.fetch(:recipe)
      chef_config_file = options.fetch(:chef_config_file)
      dna_json_file = options.fetch(:dna_json_file)

      shellout = []
      shellout << 'chef-client -z'
      shellout << "-c #{chef_config_file}"
      shellout << '--force-formatter'
      shellout << "-j #{dna_json_file}"
      shellout << "-o #{recipe}"

      Mixlib::ShellOut.new(shellout.join(' '), cwd: cwd, live_stream: $stdout)
    end

    def temp_dir
      File.join(acceptance_cookbook.root_dir, 'tmp')
    end

    def chef_dir
      File.join(temp_dir, '.chef')
    end

    def chef_config_file
      File.expand_path(File.join(chef_dir, 'config.rb'))
    end

    def dna_json_file
      File.expand_path(File.join(temp_dir, 'dna.json'))
    end
  end
end
