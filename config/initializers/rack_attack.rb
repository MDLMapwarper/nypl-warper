module Rack::Attack
  # Expose the warper app so we can call it
  class << self
    attr_accessor :app
    def app
      @app
    end
  end
end

if APP_CONFIG["enable_throttling"] == true
  
  limit = APP_CONFIG["throttle_limit"] || 5
  period = APP_CONFIG["throttle_period"] || 20
  delay = APP_CONFIG["throttle_delay"] || 2

  Rack::Attack.cache.store = ActiveSupport::Cache::RedisStore.new("127.0.0.1")

  #general rate limiting 300 requests in 5 minutes
  #uncomment to enable
  #Rack::Attack.throttle('req/ip', :limit => 300, :period => 5.minutes) do |req|
  #  req.ip + req.user_agent unless req.path.include?("/assets") || req.path.include?("/wms") || req.path.include?("/tile")
  #end

  # Attacks on logins
  Rack::Attack.throttle('logins/ip', :limit => 15, :period => 60.seconds) do |req|
    if req.path.include?('/u/sign_in') && req.post?
      req.ip + req.user_agent.to_s
    end
  end

  #  Limiting other requests, posts
  Rack::Attack.throttle('warper/post_request', :limit => limit, :period => period.seconds) do |req|
    if req.path.include?("/rectify") || 
        req.path.include?("/save_mask_and_warp") || 
        req.path.include?("/comments") ||
        req.path.include?("/gcps/add")  && req.post?
      req.ip + req.user_agent.to_s
    end
  end

  #  Limiting other requests, puts
  Rack::Attack.throttle('warper/put_request', :limit => limit, :period => period.seconds) do |req|
    if req.path.include?("/rectify") || req.path.include?("/gcps/update") | req.path.include?("/comments") && req.put?
      req.ip + req.user_agent.to_s
    end
  end
  
  Rack::Attack.throttle('warper/delete_request', :limit => limit, :period => period.seconds) do |req|
    if  (req.path.include?("/maps") || req.path.include?("/gcps")) && req.delete?
      req.ip + req.user_agent.to_s
    end
  end

  #  Limiting requests, admin throttle test
  Rack::Attack.throttle('admin/throttletest', :limit => limit, :period => period.seconds) do |req|
    if req.path.include?('/admin/throttle_test') && req.get?
      req.ip + req.user_agent.to_s
    end
  end

  Rack::Attack.throttled_response = lambda do |env|
    
    puts "throttled response with delay #{delay}" 
    sleep(delay)
  
    puts body = [
      env['rack.attack.matched'],
      env['rack.attack.match_type'],
      env['rack.attack.match_data']
    ].inspect
    
    if  ["admin/throttletest", "warper/put_request", "warper/post_request"].include?(env['rack.attack.matched'])
      env['rack.attack.flag_user'] = true
      puts "allowing call"
      Rack::Attack.app.call(env)
    else
      [ 503, {}, nil]
    end
  
  end
end