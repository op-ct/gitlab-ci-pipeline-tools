#!/usr/bin/env ruby
require 'gitlab'
require_relative 'lib/gitlab_client_helper.rb'

class GitLabGroupGithubIntegration
  # Array or regexes
  SKIPPED_PROJECTS = [
    /activemq/,
    /augeasproviders/,
    /binford2k-node_encrypt/,
    /jenkins/,
    /puppetlabs-/,
    /puppet-/,
    /mcollective/,
    /remote-gitlab-ci/,
    /\Areleng-misc\Z/,
    /\Asimp-integration-test\Z/,
    /\Asimp-(artwork|metadata)\Z/
  ]

  def initialize(options)
    @options = options
    @client_helper = GitLabClientHelper.new(options)
    @client        = @client_helper.client
  end

  def ensure!(dry_run = true)
    warn( "acquiring group projects")
    projects = @client_helper.projects_for_group

    warn("checking github service integration")
    token = ENV['GITHUB_GITLAB_EXTERNAL_CICD_TOKEN']
    # TODO: move this into a method so it doesn't fail when we don't need it
    if token.to_s.empty?
      fail 'No token found in GITHUB_GITLAB_EXTERNAL_CICD_TOKEN'
    end

    name_padding = projects.map{|x| x['name'].to_s.size }.max + 2

    projects.each do |project|
      if SKIPPED_PROJECTS.any?{ |re| re =~ project['name'] }
        warn( "!! SKIPPING #{project['name']} (matches SKIPPED_PROJECTS)" )
        next
      end
      print "== #{project['name'].ljust(name_padding)}"

      # Workaround: Sometimes .service just returns `false` instead of a data structure with a nil 'id'
      raw_github_integration = @client.service(project['id'], :github)
      unless raw_github_integration
        puts " !!!!!! client.service(project['id'], :github) returned false (investigate later) !!!!"
        next
        require 'pry'; binding.pry
      end

      github_integration        = raw_github_integration.to_h
      has_github_integration    = !github_integration['id'].nil?
      github_integration_status = has_github_integration ? github_integration['properties']['repository_url'] : '**NO GITHUB INTEGRATION**'
      puts "    #{github_integration_status}"

      # puts "   - #{project['web_url']}/-/settings/integrations"
      unless has_github_integration
        skip = dry_run
        puts "   - #{project['web_url']}"
        if skip
          warn "   - SKIPPING: because dry_run = true"
          next
        end
        # https://docs.gitlab.com/ee/api/services.html#createedit-github-service
        github_url = project['web_url'].gsub('gitlab.com', 'github.com')

        begin
          @client.change_service(project['id'], :github, { token: token, repository_url: github_url, static_context: true })
          github_integration = @client.service(project['id'], 'github').to_h
          github_integration_status = !github_integration['id'].nil? ? github_integration['properties']['repository_url'] : '**NO GITHUB INTEGRATION**'
          puts "  -- Updated: #{project['name'].ljust(name_padding-11)}   #{github_integration_status}"
        rescue Gitlab::Error::Forbidden => e
          warn
          warn 'ERROR: Failed to set up missing Gitlab CI/CD <-> GitHub Integration!'
          warn
          warn '   HINTS:'
          warn '       * Make sure you are using a **GitLab** API token with read-write scope'
          warn "       * To set up the GitHub integration for this repo using the web UI, go to #{project['web_url']}/-/services/github/edit"
          warn "\n#{e.message.gsub(/^/,' '*9)}\n\n"
          raise e
        end
      end
      project
    end
  end
end

options = GitLabClientOptionsParser.new.parse!
github_integrations_for_gitlab_group = GitLabGroupGithubIntegration.new(options)

# Default to dry run, unless DRY_RUN is set to 'yes'
github_integrations_for_gitlab_group.ensure! ( ENV['DRY_RUN'].nil? || ENV['DRY_RUN'] == 'yes')
