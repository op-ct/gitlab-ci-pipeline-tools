require 'gitlab'
require 'optparse'

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
      opts.banner = [
        'Usage:',
        '',
        "       GITLAB_TOKEN=xxx \\",
        "       [GITHUB_GITLAB_EXTERNAL_CICD_TOKEN=yyy] \\",
        "          #{$PROGRAM_NAME} [OPTIONS]",
        '',
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

      opts.on('-e', '--endpoint=val', String,
        'GitLab API endpoint',
        "Defaults to #{@options[:endpoint]}") do |e|
        @options[:endpoint] = e
      end

      opts.on('-v', '--[no-]verbose', 'Run verbosely') do |v|
        @options[:verbose] = v
      end

      opts.on('-h', '--help', 'Print (this) help message') do
        puts opts
        exit
      end
    end.parse!

    # allow environment variables for these two options in particular
    @options[:token] = ENV['GITLAB_TOKEN'] || ENV['GITLAB_API_PRIVATE_TOKEN']

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
    r = client.search_in_group( grp['id'], 'projects', project_name )
    fail ("Expected 1 project to match '#{project}'") unless r.size == 1
    r.first.to_h
  end

  # @return [Array<Hash>] All projects for the group
  def projects_for_group(group=@options[:group])
    paginated_projects = client.group_projects(group, order_by: 'name', sort: 'asc')
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
