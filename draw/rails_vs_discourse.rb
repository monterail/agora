require "sequel"
require "pg"
require "pry"
require "rubyvis"
require "date"
require "fileutils"

DB = Sequel.connect(ENV["DATABASE_URL"])

def cache(key, &block)
  file = "rails_vs_discourse-#{key}.cache"
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

discourse_users = cache "discourse_users" do
  DB[<<-EOS].to_a.map {|e| e[:actor]}
    SELECT actor
    FROM rawevents
    WHERE repo LIKE 'https://github.com/discourse/%'
      AND type != 'WatchEvent'
      AND type != 'ForkEvent'
      AND actor NOT IN ('discoursebot', 'discoursebuild')
    GROUP BY actor
    ORDER BY COUNT(*) DESC
    LIMIT 100
  EOS
end

discourse_events = cache "discourse_events" do
  DB[<<-EOS, discourse_users].to_a
    SELECT date, count(*) AS cnt
    FROM rawevents
    WHERE repo LIKE 'https://github.com/discourse/%'
      AND type != 'WatchEvent'
      AND type != 'ForkEvent'
      AND actor IN ?
    GROUP BY date
  EOS
end

rails_events = cache "rails_events" do
  DB[<<-EOS, discourse_users].to_a
    SELECT date, count(*) AS cnt
    FROM rawevents
    WHERE repo LIKE 'https://github.com/rails/%'
      AND type != 'WatchEvent'
      AND type != 'ForkEvent'
      AND actor IN ?
    GROUP BY date
  EOS
end


range  = (Date.new(2013, 01, 01)..Date.new(2014, 07, 31))
file = "graphs/discourse_rails.svg"
vis = Rubyvis::Panel.new.width(1800).height(800 + 20)

[
  ["discourse", discourse_events, "#00f"],
  ["rails", rails_events, "#f00"]
].each.with_index do |(label, events, fill), index|
  data = events.inject({}) {|h, e| h.merge(e[:date] => e[:cnt])}

  series = range.map do |date|
    data[date] || 0
  end

  offset = index * 400 + 20

  vis.add(pv.Bar).
    data(series).
    width(3).
    height(->(d){3*d}).
    bottom(offset + 10).
    fill_style(fill).
    left(->(){ 20 + self.index * 3 })

  vis.add(pv.Rule).
    bottom(offset + 10).
    left(0).
    width(1800).
    stroke_style("#ccc")


  vis.add(pv.Label).
    text(label).
    bottom(offset - 10).
    left(0)
end

vis.render
File.open(file, "w") {|f| f.puts vis.to_svg }
