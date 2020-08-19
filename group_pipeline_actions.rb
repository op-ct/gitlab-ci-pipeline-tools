#!/usr/bin/env ruby
require 'gitlab'
require_relative 'lib/gitlab_client_helper.rb'

class GitLabPipelineActions
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

  def select_projects( projects, skipped_projects )
    warn("skipping SKIPPED_PROJECTS")
    name_padding = projects.map{|x| x['name'].to_s.size }.max + 2
    last_ok = nil
    projects.select do |project|
      if skipped_projects.any?{ |re| re =~ project['name'] }
        warn("\n") if last_ok
        warn( "!! SKIPPING #{project['name']} (matches skipped_projects)" )
        last_ok = false
        false
      else
        #print "== #{project['name'].ljust(name_padding)}"
        print " #{project['name']},"
        last_ok = true
      end
    end
  end

  # scopes can be:
  def project_ref_pipelines( project, ref, scopes=[] )
    pipelines = []
    warn "- looking up running/pending pipelines for project '#{project['name']}"
    if scopes.empty?
      pipelines += @client.pipelines(project['id'], scope: 'running', ref: ref)
    else
      scopes.each do |scope|
        pipelines += @client.pipelines(project['id'], scope: scope, ref: ref)
      end
    end
 #   require 'pry'; binding.pry unless pipelines.empty?
    [project['name'], pipelines] unless pipelines.empty?
  end


  # cancel pipeline jobs for ref named `ref` across all of the group's projects
  def cancel!(ref = 'SIMP-7974')
    warn( "acquiring group projects")
    projects = select_projects( @client_helper.projects_for_group, SKIPPED_PROJECTS )

    pupmod_projects = projects.select{|x| x['name'] =~ /\Apupmod-simp/}
    warn pupmod_projects.map{|x| x['name']}.sort

    target_project_pipelines = projects.map do |project|
      project_ref_pipelines(project, ref, ['pending', 'running'])
    end

    project_pipelines = Hash[target_project_pipelines.reject(&:nil?)]
    project_pipelines.each do |proj_name, pipelines|
      project =  projects.select{ |x| x['name'] == proj_name }.first
      pipelines.each do |pipeline|
        warn "!! Cancelling pipeline #{pipeline['id']}: #{pipeline['web_url']}"
        @client.cancel_pipeline(project['id'], pipeline['id'])
      end

    end
    require 'pry'; binding.pry

###      # Workaround: Sometimes .service just returns `false` instead of a data structure with a nil 'id'
###      raw_github_integration = @client.service(project['id'], :github)
###      unless raw_github_integration
###        puts " !!!!!! client.service(project['id'], :github) returned false (investigate later) !!!!"
###        next
###        require 'pry'; binding.pry
###      end
###
###      github_integration = raw_github_integration.to_h
###      gh_int = !github_integration['id'].nil?
###      gh_int_status = gh_int ? github_integration['properties']['repository_url'] : '**NO GITHUB INTEGRATION**'
###      puts "    #{gh_int_status}"
###
###      # puts "   - #{project['web_url']}/-/settings/integrations"
###      unless gh_int
###        skip = dry_run
###        puts "   - #{project['web_url']}"
###        if skip
###          warn "   - SKIPPING: because dry_run = true"
###          next
###        end
###        # https://docs.gitlab.com/ee/api/services.html#createedit-github-service
###        github_url = project['web_url'].gsub('gitlab.com', 'github.com')
###
###        begin
###          @client.change_service(project['id'], :github, { token: token, repository_url: github_url, static_context: true })
###          github_integration = @client.service(project['id'], 'github').to_h
###          gh_int_status = !github_integration['id'].nil? ? github_integration['properties']['repository_url'] : '**NO GITHUB INTEGRATION**'
###          puts "  -- Updated: #{project['name'].ljust(name_padding-11)}   #{gh_int_status}"
###        rescue Gitlab::Error::Forbidden => e
###          warn
###          warn 'ERROR: Failed to set up missing Gitlab CI/CD <-> GitHub Integration!'
###          warn
###          warn '   HINTS:'
###          warn '       * Make sure you are using a **GitLab** API token with read-write scope'
###          warn "       * To set up the GitHub integration for this repo using the web UI, go to #{project['web_url']}/-/services/github/edit"
###          warn "\n#{e.message.gsub(/^/,' '*9)}\n\n"
###          raise e
###        end
###      end
###      project
###    end
  end
end

options = GitLabClientOptionsParser.new.parse!
gitlab_pipeline_actions = GitLabPipelineActions.new(options)
gitlab_pipeline_actions.ensure!
