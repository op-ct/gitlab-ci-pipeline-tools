#!/usr/bin/env ruby
require 'gitlab'
require_relative 'lib/gitlab_client_helper.rb'

class GitLabGroupGithubIntegration
  # Array or regexes
  SKIPPED_PROJECTS = [
    /activemq/,
    /augeasproviders/,
    /binford2k-node_encrypt/,
    /gitlab-oss/,
    /jenkins/,
    /mcollective/,
    /puppet-/,
    /puppetlabs-/,
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

  def github_token
    return @github_token if @github_token
    @github_token = ENV['GITHUB_GITLAB_EXTERNAL_CICD_TOKEN']
    if github_token.to_s.empty?
      fail 'No token found in GITHUB_GITLAB_EXTERNAL_CICD_TOKEN'
    end
    @github_token
  end

  def ensure_projects!(project_names, dry_run)
    name_padding = project_names.map{|x| x.to_s.size }.max + 2

    project_names.map do |project_name|
      warn( "acquiring group project '#{project_name}'")
      project = @client_helper.project_under_group( project_name )
      result = ensure_project!(project, name_padding, dry_run, true)
    require 'pry'; binding.pry
    end
  end


  def ensure!(dry_run)
    warn( "acquiring group projects")
    projects = @client_helper.projects_for_group
    warn("checking github service integration")

    name_padding = projects.map{|x| x['name'].to_s.size }.max + 2
    projects.map do |project|
      ensure_project!(project, name_padding, dry_run, force)
    end
  end

  def ensure_project!( project, name_padding, dry_run, force=false )
      if SKIPPED_PROJECTS.any?{ |re| re =~ project['name'] }
        warn( "!! SKIPPING #{project['name']} (matches SKIPPED_PROJECTS)" )
        return
      end
      print "== #{project['name'].ljust(name_padding)}"

      # Workaround: Sometimes .service just returns `false` instead of a data structure with a nil 'id'
      raw_github_integration = @client.service(project['id'], :github)
      unless raw_github_integration
        puts " !!!!!! client.service(project['id'], :github) returned false (investigate later) !!!!"
        return
        require 'pry'; binding.pry
      end

      github_integration        = raw_github_integration.to_h
      has_github_integration    = !github_integration['id'].nil?
      github_integration_status = has_github_integration ? github_integration['properties']['repository_url'] : '**NO GITHUB INTEGRATION**'
      puts "    #{github_integration_status}"

    require 'pry'; binding.pry
      # puts "   - #{project['web_url']}/-/settings/integrations"
      unless has_github_integration && !force
        puts "   - #{project['web_url']}"
        if dry_run
          warn "   - SKIPPING: because dry_run = true"
          return
        end
        if has_github_integration && force
          warn "   - FORCING: API update over previous integration"
        end

        # https://docs.gitlab.com/ee/api/services.html#createedit-github-service
        github_url = project['web_url'].gsub('gitlab.com', 'github.com')

        begin
          @client.change_service(project['id'], :github, { token: github_token, repository_url: github_url, static_context: true })
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

options = GitLabClientOptionsParser.new.parse!
github_integrations_for_gitlab_group = GitLabGroupGithubIntegration.new(options)

# Default to dry run, unless DRY_RUN is set to 'yes'
dry_run  = ( ENV['DRY_RUN'].nil? || ENV['DRY_RUN'] == 'yes')
if ARGV.empty?
  github_integrations_for_gitlab_group.ensure!(dry_run)
else
  github_integrations_for_gitlab_group.ensure_projects!(ARGV, dry_run)
end
