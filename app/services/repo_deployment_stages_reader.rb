class RepoDeploymentStagesReader
  CONFIG_FILE = SyrusYml::CONFIG_FILE
  CACHE_TTL = 5.minutes
  @cache_mutex = Mutex.new
  @process_cache = {}

  Result = Data.define(:stages, :source, :note) do
    def enabled?
      stages.any?
    end
  end

  def self.for_repository(repository, cached: true)
    return new(repository: repository, user: repository.user).resolve unless cached

    key = cache_key(repository)
    return new(repository: repository, user: repository.user).resolve unless key

    fetch_process_cache(key, now: Time.current) do
      new(repository: repository, user: repository.user).resolve
    end
  end

  def self.clear_cache!(repository = nil)
    @cache_mutex.synchronize do
      if repository
        key = cache_key(repository)
        @process_cache.delete(key) if key
      else
        @process_cache = {}
      end
    end
  end

  def self.cache_key(repository)
    return unless repository&.id

    [ repository.id, repository.default_branch.to_s ]
  end
  private_class_method :cache_key

  def self.fetch_process_cache(key, now:)
    entry = @cache_mutex.synchronize do
      cached = @process_cache[key]
      cached if cached && cached[:expires_at] > now
    end
    return entry[:value] if entry

    value = yield
    @cache_mutex.synchronize do
      @process_cache[key] = { value: value, expires_at: now + CACHE_TTL }
    end
    value
  end
  private_class_method :fetch_process_cache

  def initialize(repository:, user:, client: nil)
    @repository = repository
    @user = user
    @client = client
  end

  def resolve
    return disabled(source: "none", note: "no GitHub credentials") unless credentials_available?

    client = github_client
    return disabled(source: "none", note: "GitHub client unavailable") unless client

    file = client.file_content_at(repository.slug, CONFIG_FILE, repository.default_branch)
    return disabled(source: "none", note: "no .syrus.yml") unless file

    stages = SyrusYml.new(file.fetch(:content)).parse.deployment_stages
    return disabled(source: ".syrus.yml", note: "no deployment_stages configured") if stages.empty?

    Result.new(stages: stages, source: ".syrus.yml", note: nil)
  rescue SyrusYml::ParseError => e
    disabled(source: ".syrus.yml", note: e.message)
  rescue StandardError => e
    Rails.logger.warn("[RepoDeploymentStagesReader] disabled for #{repository.slug}: #{e.class}: #{e.message}")
    disabled(source: "none", note: e.message)
  end

  private

  attr_reader :repository, :user

  def github_client
    return @client if @client

    client = GithubClient.for(repository: repository, user: user)
    client if client.is_a?(GithubClient)
  end

  def credentials_available?
    repository.installation&.active? || user.github_token.present?
  end

  def disabled(source:, note:)
    Result.new(stages: [], source: source, note: note)
  end
end
