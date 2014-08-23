#!/usr/bin/env ruby -w
# encoding: UTF-8
#
# = ActivitiesDB.rb -- PostRunner - Manage the data from your Garmin sport devices.
#
# Copyright (c) 2014 by Chris Schlaeger <cs@taskjuggler.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of version 2 of the GNU General Public License as
# published by the Free Software Foundation.
#

require 'yaml'
require 'fit4ruby'

module PostRunner

  # Simple class to manage runtime configuration options which are persisted
  # in a YAML file.
  class RuntimeConfig

    # Create a new RC object.
    # @param dir [String] the directory to hold the config.yml file.
    def initialize(dir)
      @options = {
        :unit_system => :metric,
        :import_dir => nil
      }
      @config_file = File.join(dir, 'config.yml')

      load_options if File.exist?(@config_file)
    end

    # Get a config option value.
    # @param name [Symbol] the name of the config option.
    # @return [Object] the value of the config option.
    def get_option(name)
      @options[name]
    end

    # Set a config option and update the RC file.
    # @param name [Symbol] The name of the config option.
    # @param value [Object] The value of the config option.
    def set_option(name, value)
      @options[name] = value
      save_options
    end

    private

    def load_options
      begin
        opts = YAML::load_file(@config_file)
      rescue IOError
        Log.error "Cannot load config file '#{@config_file}': #{$!}"
      end
      # Merge the loaded options into the @options hash.
      opts.each { |key, value| @options[key] = value }
    end

    def save_options
      begin
        File.write(@config_file, @options.to_yaml)
        Log.info "Runtime config file '#{@config_file}' written"
      rescue
        Log.error "Cannot write config file '#{@config_file}': #{$!}"
      end
    end

  end

end
