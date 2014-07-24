require 'rhc/git_helpers'
require 'rhc/server_helpers'

module RHC
  #
  # Methods in this module should not attempt to read from the options hash
  # in a recursive manner (server_context can't read options.server).
  #
  module ContextHelpers
    include RHC::GitHelpers
    include RHC::ServerHelpers

    def self.included(other)
      other.module_eval do
        def self.takes_team(opts={})
          if opts[:argument]
            argument :team_name, "Name of a team", ["-t", "--team-name NAME"], :allow_nil => true, :covered_by => :team_id
          else
            #:nocov:
            option ["-t", "--team-name NAME"], "Name of a team", :covered_by => :team_id
            #:nocov:
          end
          option ["--team-id ID"], "ID of a team", :covered_by => :team_name
        end

        def self.takes_domain(opts={})
          if opts[:argument]
            argument :namespace, "Name of a domain", ["-n", "--namespace NAME"], :allow_nil => true, :default => :from_local_git
          else
            #:nocov:
            option ["-n", "--namespace NAME"], "Name of a domain", :default => :from_local_git
            #:nocov:
          end
        end

        def self.takes_membership_container(opts={})
          if opts && opts[:argument]
            if opts && opts[:writable]
              #:nocov:
              argument :namespace, "Name of a domain", ["-n", "--namespace NAME"], :allow_nil => true, :default => :from_local_git
              #:nocov:
            else
              argument :target, "The name of a domain, or an application name with domain (domain or domain/application)", ["--target NAME_OR_PATH"], :allow_nil => true, :covered_by => [:application_id, :namespace, :app]
            end
          end
          option ["-n", "--namespace NAME"], "Name of a domain"
          option ["-a", "--app NAME"], "Name of an application" unless opts && opts[:writable]
          option ["-t", "--team-name NAME"], "Name of a team"
          option ["--team-id ID"], "ID of a team"
        end

        def self.takes_application(opts={})
          if opts[:argument]
            argument :app, "Name of an application", ["-a", "--app NAME"], :allow_nil => true, :default => :from_local_git, :covered_by => :application_id
          else
            option ["-a", "--app NAME"], "Name of an application", :default => :from_local_git, :covered_by => :application_id
          end
          option ["-n", "--namespace NAME"], "Name of a domain", :default => :from_local_git
          option ["--application-id ID"], "ID of an application", :hide => true, :default => :from_local_git, :covered_by => :app
        end
      end
    end

    def find_team(opts={})
      if id = options.team_id.presence
        return rest_client.find_team_by_id(id, opts)
      end
      team_name = (opts && opts[:team_name]) || options.team_name
      if team_name.present?
        rest_client.find_team(team_name, opts)
      else
        raise ArgumentError, "You must specify a team name with -t, or a team id with --team-id."
      end
    end

    def find_domain(opts={})
      domain = options.namespace || options.target || namespace_context
      if domain
        rest_client.find_domain(domain)
      else
        raise ArgumentError, "You must specify a domain with -n."
      end
    end

    def find_membership_container(opts={})
      domain, app = discover_domain_and_app
      if options.team_id.present?
        rest_client.find_team_by_id(options.team_id)
      elsif options.team_name.present?
        rest_client.find_team(options.team_name)
      elsif app && domain
        rest_client.find_application(domain, app)
      elsif domain
        rest_client.find_domain(domain)
      elsif opts && opts[:writable]
        raise ArgumentError, "You must specify a domain with -n, or a team with -t."
      else
        raise ArgumentError, "You must specify a domain with -n, an application with -a, or a team with -t."
      end
    end

    def find_app(opts={})
      if id = options.application_id.presence
        if opts.delete(:with_gear_groups)
          return rest_client.find_application_by_id_gear_groups(id, opts)
        else
          return rest_client.find_application_by_id(id, opts)
        end
      end
      option = (opts && opts[:app]) || options.app
      domain, app =
        if option
          if option =~ /\//
            option.split(/\//)
          else
            [options.namespace || namespace_context, option]
          end
        end
      if app.present? && domain.present?
        if opts.delete(:with_gear_groups)
          rest_client.find_application_gear_groups(domain, app, opts)
        else
          rest_client.find_application(domain, app, opts)
        end
      else
        raise ArgumentError, "You must specify an application with -a, or run this command from within Git directory cloned from OpenShift."
      end
    end

    def server_context(defaults=nil, arg=nil)
      value = libra_server_env || (!options.clean && config['libra_server']) || openshift_online_server
      defaults[arg] = value if defaults && arg
      value
    end

    def from_local_git(defaults, arg)
      @local_git_config ||= {
        :application_id => git_config_get('rhc.app-id').presence,
        :app => git_config_get('rhc.app-name').presence,
        :namespace => git_config_get('rhc.domain-name').presence,
      }
      defaults[arg] ||= @local_git_config[arg] unless @local_git_config[arg].nil?
      @local_git_config
    end

    def namespace_context
      # right now we don't have any logic since we only support one domain
      # TODO: add domain lookup based on uuid
      domain = rest_client.domains.first
      raise RHC::NoDomainsForUser if domain.nil?

      domain.name
    end

    def discover_domain_and_app
      if options.target.present?
        options.target.split(/\//)
      elsif options.namespace || options.app
        if options.app =~ /\//
          options.app.split(/\//)
        else
          [options.namespace || namespace_context, options.app]
        end
      end
    end
  end
end
