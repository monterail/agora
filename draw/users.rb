require "sequel"
require "pg"
require "pry"
require "rubyvis"
require "date"
require "fileutils"

DB = Sequel.connect(ENV["DATABASE_URL"])
SCOPE = "rails"

FileUtils.mkdir_p("graphs/#{SCOPE}")

def cache(key, &block)
  file = "#{SCOPE}-#{key}.cache"
  if File.exists?(file)
    puts "Loading #{file}"
    Marshal.load(File.read(file))
  else
    puts "Running #{key}"
    data = block.call
    puts "Saving #{key}"
    File.open(file, "w"){|f| f.write Marshal.dump(data)}
    data
  end
end


users = cache "users" do
  DB[<<-EOS].to_a
    SELECT actor, count(*) AS cnt
    FROM rawevents
    WHERE repo LIKE 'https://github.com/#{SCOPE}/%'
      AND type != 'WatchEvent'
      AND type != 'ForkEvent'
    GROUP BY actor
    ORDER BY cnt DESC
    LIMIT 100
  EOS
end


users_with_repos = cache "users_with_repos" do
  users.map.with_index do |user, index|
    puts "users_with_repos #{index+1}"

    repos = DB[<<-EOS, user[:actor]].to_a.reject {|r| !r[:repo] || r[:cnt] < 10 }
      select repo, count(*) as cnt
      from rawevents
      where actor = ?
      group by repo
      order by cnt desc
    EOS

    user.merge(repos: repos)
  end
end


users_with_repos_with_dates = cache "users_with_repos_with_dates" do
  users_with_repos.map.with_index do |user, index|
    puts "users_with_repos_with_dates #{index+1}"

    repos = user[:repos].map do |repo|
      points = DB[<<-EOS, user[:actor], repo[:repo]].to_a
        select date, count(*) as count
        from rawevents
        where actor = ? and repo = ?
        group by repo, date
      EOS

      repo.merge(points: points)
    end

    user.merge(repos: repos)
  end
end

users_in_scope = users_with_repos_with_dates.map do |user|
  puts "User #{user[:actor]}"

  scope_points = Hash.new { 0 }
  repos = []

  user[:repos].each do |repo|
    m = repo[:repo].match(/^.*?([^\/]+)\/([^\/]+)$/)
    org, name = m[1], m[2]

    if org == SCOPE
      repo[:points].each do |p|
        scope_points[p[:date]] = p[:count]
      end
    else
      rep = {name: "#{org}/#{name}"}
      rep[:points] = repo[:points].inject({}) do |h,p|
        h.merge(p[:date] => p[:count])
      end

      repos << rep
    end
  end

  repos.unshift({name: "#{SCOPE}/*", points: scope_points})

  repos.each do |rep|
    puts "  #{rep[:name]} #{rep[:points].size}"
  end

  user.merge(repos: repos)
end


range  = (Date.new(2013, 01, 01)..Date.new(2014, 07, 31))

users_in_scope.each.with_index do |user, index|
  puts "Plotting #{user[:actor]} (#{index+1})"
  file = "graphs/#{SCOPE}/#{user[:actor]}.svg"

  s = user[:repos].size
  vis = Rubyvis::Panel.new.width(1800).height(s*300)

  user[:repos].reverse.each.with_index do |repo, index|
    data = range.map do |date|
      repo[:points][date] || 0
    end

    offset = index * 300

    vis.add(pv.Bar).
      data(data).
      width(3).
      height(->(d){3*d}).
      bottom(offset + 10).
      left(->(){ 20 + self.index * 3 })

    vis.add(pv.Rule).
      bottom(offset + 10).
      left(0).
      width(1800).
      stroke_style("#ccc")


    vis.add(pv.Label).
      text(repo[:name]).
      bottom(offset - 10).
      left(0)
  end

  vis.render
  File.open(file, "w") {|f| f.puts vis.to_svg }
end
