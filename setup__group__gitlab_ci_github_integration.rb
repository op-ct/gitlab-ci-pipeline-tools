#!/usr/bin/env ruby
require 'gitlab'
require 'optparse'

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

class GitLabClientOptionsParser
  attr_reader :options

  OPTION_DEFAULTS = {
    :group => 'simp',
    :debug => false,
  }

  def initialize(instance_defaults={})
    @options = OPTION_DEFAULTS.merge(
      { endpoint: ENV['GITLAB_URL'] || ENV['GITLAB_API_ENDPOINT'] || 'https://gitlab.com/api/v4' }
    ).merge(instance_defaults)
  end

  def parse!
    OptionParser.new do |opts|
      program = File.basename(__FILE__)
      opts.banner = [
        "Usage: #{program} [OPTIONS] -t USER_GITLAB_API_TOKEN",
        "       GITLAB_TOKEN=USER_GITLAB_API_TOKEN #{program} [OPTIONS]"
      ].join("\n")

      opts.separator("\n")

      opts.on('-o', '--group=val', String,
        'GitLab group to query against.',
        "Defaults to '#{@options[:group]}'") do |o|
        @options[:group] = o
      end

      opts.on('-p', '--pipeline=val', String,
        'Which pipeline to grab: latest, latest-tag, or master',
        "Defaults to '#{@options[:report_on]}'") do |p|
        @options[:report_on] = p
      end

      opts.on('-t', '--token=val', String, 'GitLab API token') do |t|
        @options[:token] = t
      end

      opts.on('-e', '--endpoint=val', String,
        'GitLab API endpoint',
        "Defaults to #{@options[:endpoint]}") do |e|
        @options[:endpoint] = e
      end

      opts.on('-v', '--[no-]verbose', 'Run verbosely') do |v|
        @options[:verbose] = v
      end

      opts.on('-h', '--help', 'Print this menu') do
        puts opts
        exit
      end
    end.parse!

    # allow environment variables for these two options in particular
    unless @options[:token]
      @options[:token] = ENV['GITLAB_TOKEN'] || ENV['GITLAB_API_PRIVATE_TOKEN']
    end

    @options
  end
end

class GitLabClientHelper
  attr_accessor :client
  def initialize( options )
    @options = options
  end

  def client
    @client ||= Gitlab.client(
      endpoint: @options[:endpoint],
      private_token: @options[:token]
    )
  end

  # @return [Hash] group data
  # @raise [RuntimeError] if the group was not found
  def group(group=@options[:group])
    r = client.group_search(group)
    fail ("Expected 1 group to match '#{group}'") unless r.size == 1
    r.first.to_h
  end

  # @return [Hash] project data
  # @raise [RuntimeError] if the project was not found under the group
  def project_under_group(project_name,group_name=@options[:group])
    grp = group(group_name)
    r = grp.search_in_group( grp['id'], 'projects', project_name )
    fail ("Expected 1 project to match '#{project}'") unless r.size == 1
    r.first.to_h
  end

  # @return [Array<Hash>] All projects for the group
  def projects_for_group(group=@options[:group])
    paginated_projects = client.group_projects(group)
    projects = []
    while paginated_projects.has_next_page?
      projects += paginated_projects.to_a.map(&:to_h)
      paginated_projects = paginated_projects.next_page
    end
    projects += paginated_projects.to_a.map(&:to_h)
    if block_given?
      projects = projects.map {|project| yield(project, client); project}
    end
    projects
  end

end

class GitLabGroupGithubIntegration
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

      github_integration = raw_github_integration.to_h
      gh_int = !github_integration['id'].nil?
      gh_int_status = gh_int ? github_integration['properties']['repository_url'] : '**NO GITHUB INTEGRATION**'
      puts "    #{gh_int_status}"

      # puts "   - #{project['web_url']}/-/settings/integrations"
      unless gh_int
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
          gh_int_status = !github_integration['id'].nil? ? github_integration['properties']['repository_url'] : '**NO GITHUB INTEGRATION**'
          puts "  -- Updated: #{project['name'].ljust(name_padding-11)}   #{gh_int_status}"
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
github_integrations_for_gitlab_group.ensure!
