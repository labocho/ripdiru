#!/usr/bin/env ruby

require "ripdiru/version"
require 'uri'
require 'pathname'
require 'open-uri'
require 'date'
require 'fileutils'
require 'json'
require 'active_support/duration'

module Ripdiru
  class DownloadTask

    TMPDIR = ENV['TMPDIR'] || '/tmp'
    SCHEDULE_URL = "http://www2.nhk.or.jp/hensei/api/noa.cgi?c=3&wide=1&mode=json"

    attr_accessor :station, :cache, :buffer, :outdir, :bitrate

    def initialize(station = nil, duration = 1800, *args)
      unless station
        abort "Usage: ripdiru [station-id]"
      end
      @station = station
      @channel = channel
      @duration = duration
      @cache = CacheDir.new(TMPDIR)
      @buffer = ENV['RIPDIRU_BUFFER'] || 60
      @outdir = ENV['RIPDIRU_OUTDIR'] || "#{ENV['HOME']}/Music/Radiru"
      @bitrate = ENV['RIPDIRU_BITRATE'] || '48k'
    end

    def channel
      case station
        when "NHK1"
          @playlist="https://radio-stream.nhk.jp/hls/live/2023507/nhkradiruakr1/master48k.m3u8"
        when "NHK2"
          @playlist="https://radio-stream.nhk.jp/hls/live/2023507/nhkradiruakr2/master48k.m3u8"
        when "FM"
          @playlist="https://radio-stream.nhk.jp/hls/live/2023507/nhkradiruakfm/master48k.m3u8"
        else
          puts "invalid channel"
      end
    end

    def now_playing(station)
      now = Time.now

      json = JSON.parse(URI.open("https://api.nhk.jp/r7/pg/now/radio/130/now.json", &:read))
      key = case station
      when "NHK1"
        "r1"
      when "NHK2"
        "r2"
      when "FM"
        "r3"
      end

      program = json.fetch(key).fetch("present")

      Program.new(
        id: now.strftime("%Y%m%d%H%M%S") + "-#{station}",
        station: station,
        title: program.fetch("name"),
        from: Time.parse(program.fetch("startDate")),
        to: Time.parse(program.fetch("endDate")),
        duration: ActiveSupport::Duration.parse(program.fetch("duration")).to_i,
        info: program.fetch("url"),
      )
    end

    def run
      program = now_playing(station)

      duration = program.recording_duration + buffer

      tempfile = "#{TMPDIR}/#{program.id}.mp3"
      puts "Streaming #{program.title} ~ #{program.to.strftime("%H:%M")} (#{duration}s)"
      puts "Ripping audio file to #{tempfile}"

      command = %W(
        ffmpeg -y -i #{@playlist} -vn
        -loglevel error
        -metadata author="NHK"
        -metadata artist="#{program.station}"
        -metadata title="#{program.title} #{program.effective_date.strftime}"
        -metadata album="#{program.title}"
        -metadata genre=Radio
        -metadata year="#{program.effective_date.year}"
        -acodec libmp3lame -ar 44100 -ab #{bitrate} -ac 2
        -id3v2_version 3
        -t #{duration}
        #{tempfile}
      )

      Signal.trap(:INT) { puts "Recording interupted by user"}
      system command.join(" ")

      FileUtils.mkpath(outdir)
      File.rename tempfile, "#{outdir}/#{program.id}.mp3"

    end

    def abort(msg)
      puts msg
      exit 1
    end
  end

  class Program
    attr_accessor :id, :station, :title, :from, :to, :duration, :info
    def initialize(args = {})
      args.each do |k, v|
        send "#{k}=", v
      end
    end

    def effective_date
      time = from.hour < 5 ? from - 24 * 60 * 60 : from
      Date.new(time.year, time.month, time.day)
    end

    def recording_duration
      (to - Time.now).to_i
    end
  end

  class CacheDir
    attr_accessor :dir
    def initialize(dir)
      @dir = dir
      @paths = {}
    end

    def [](name)
      @paths[name] ||= Pathname.new(File.join(@dir, name))
    end
  end
end
