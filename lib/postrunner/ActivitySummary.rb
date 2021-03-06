#!/usr/bin/env ruby -w
# encoding: UTF-8
#
# = ActivitySummary.rb -- PostRunner - Manage the data from your Garmin sport devices.
#
# Copyright (c) 2014 by Chris Schlaeger <cs@taskjuggler.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of version 2 of the GNU General Public License as
# published by the Free Software Foundation.
#

require 'fit4ruby'

require 'postrunner/FlexiTable'
require 'postrunner/ViewFrame'
require 'postrunner/HRV_Analyzer'
require 'postrunner/Percentiles'
require 'postrunner/HRZoneDetector'

module PostRunner

  class ActivitySummary

    class HRZone < Struct.new(:index, :low, :high, :time_in_zone,
                              :percent_in_zone)
    end

    include Fit4Ruby::Converters

    def initialize(activity, unit_system, custom_fields)
      @activity = activity
      @fit_activity = activity.fit_activity
      @name = custom_fields[:name]
      @type = custom_fields[:type]
      @sub_type = custom_fields[:sub_type]
      @unit_system = unit_system
    end

    def to_s
      s = summary.to_s + "\n" +
        (@activity.note ? note.to_s + "\n" : '') +
        laps.to_s
      s += hr_zones.to_s if has_hr_zones?

      s
    end

    def to_html(doc)
      width = 600
      ViewFrame.new('activity', "Activity: #{@name}",
                    width, summary).to_html(doc)
      ViewFrame.new('note', 'Note', width, note,
                    true).to_html(doc) if @activity.note
      ViewFrame.new('laps', 'Laps', width, laps, true).to_html(doc)
      if has_hr_zones?
        ViewFrame.new('hr_zones', 'Heart Rate Zones', width, hr_zones, true).
          to_html(doc)
      end
    end

    private

    def note
      t = FlexiTable.new
      t.enable_frame(false)
      t.body
      t.row([ @activity.note ])
      t
    end

    def summary
      session = @fit_activity.sessions[0]

      t = FlexiTable.new
      t.enable_frame(false)
      t.body
      t.row([ 'Type:', @type ])
      t.row([ 'Sub Type:', @sub_type ])
      t.row([ 'Date:', session.timestamp ])
      t.row([ 'Distance:',
              local_value(session, 'total_distance', '%.2f %s',
                          { :metric => 'km', :statute => 'mi'}) ])
      if session.has_geo_data?
        t.row([ 'GPS Data based Distance:',
                local_value(@fit_activity, 'total_gps_distance', '%.2f %s',
                            { :metric => 'km', :statute => 'mi'}) ])
      end
      t.row([ 'Time:', secsToHMS(session.total_timer_time) ])
      t.row([ 'Avg. Speed:',
              local_value(session, 'avg_speed', '%.1f %s',
                          { :metric => 'km/h', :statute => 'mph' }) ])
      if @activity.sport == 'running' || @activity.sport == 'multisport'
        t.row([ 'Avg. Pace:', pace(session, 'avg_speed') ])
      end
      t.row([ 'Total Ascent:',
              local_value(session, 'total_ascent', '%.0f %s',
                          { :metric => 'm', :statute => 'ft' }) ])
      t.row([ 'Total Descent:',
              local_value(session, 'total_descent', '%.0f %s',
                          { :metric => 'm', :statute => 'ft' }) ])
      t.row([ 'Calories:', "#{session.total_calories} kCal" ])
      t.row([ 'Avg. HR:', session.avg_heart_rate ?
              "#{session.avg_heart_rate} bpm" : '-' ])
      t.row([ 'Max. HR:', session.max_heart_rate ?
              "#{session.max_heart_rate} bpm" : '-' ])
      if @activity.sport == 'running' || @activity.sport == 'multisport'
        t.row([ 'Avg. Run Cadence:',
                session.avg_running_cadence ?
                "#{(2 * session.avg_running_cadence).round} spm" : '-' ])
        t.row([ 'Avg. Stride Length:',
                local_value(session, 'avg_stride_length', '%.2f %s',
                            { :metric => 'm', :statute => 'ft' }) ])
        t.row([ 'Avg. Vertical Oscillation:',
                local_value(session, 'avg_vertical_oscillation', '%.1f %s',
                            { :metric => 'cm', :statute => 'in' }) ])
        t.row([ 'Vertical Ratio:',
                session.vertical_ratio ?
                "#{session.vertical_ratio}%" : '-' ])
        t.row([ 'Avg. Ground Contact Time:',
                session.avg_stance_time ?
                "#{session.avg_stance_time.round} ms" : '-' ])
        t.row([ 'Avg. Ground Contact Time Balance:',
                session.avg_gct_balance ?
                "#{session.avg_gct_balance}% L / " +
                "#{100.0 - session.avg_gct_balance}% R" : ';' ])
      end
      if @activity.sport == 'cycling'
        t.row([ 'Avg. Cadence:',
                session.avg_cadence ?
                "#{(2 * session.avg_cadence).round} rpm" : '-' ])
      end

      if @fit_activity.physiological_metrics &&
         (physiological_metrics = @fit_activity.physiological_metrics.last)
        if physiological_metrics.anaerobic_training_effect
          t.row([ 'Anaerobic Training Effect:',
                  physiological_metrics.anaerobic_training_effect ])
        end
        if physiological_metrics.aerobic_training_effect
          t.row([ 'Aerobic Training Effect:',
                  physiological_metrics.aerobic_training_effect ])
        end
      elsif session.total_training_effect
        t.row([ 'Aerobic Training Effect:', session.total_training_effect ])
      end

      rec_info = @fit_activity.recovery_info
      t.row([ 'Ignored Recovery Time:',
              rec_info ? secsToDHMS(rec_info * 60) : '-' ])

      rec_hr = @fit_activity.recovery_hr
      end_hr = @fit_activity.ending_hr
      t.row([ 'Recovery HR:',
              rec_hr && end_hr ?
              "#{rec_hr} bpm [#{end_hr - rec_hr} bpm]" : '-' ])

      rec_time = @fit_activity.recovery_time
      t.row([ 'Suggested Recovery Time:',
              rec_time ? secsToDHMS(rec_time * 60) : '-' ])

      rr_intervals = @activity.fit_activity.hrv.map do |hrv|
        hrv.time.compact
      end.flatten
      hrv = HRV_Analyzer.new(rr_intervals)
      if hrv.has_hrv_data?
        t.row([ 'HRV Score:', "%.1f" % hrv.one_sigma(:hrv_score) ])
      end

      t
    end

    def laps
      session = @fit_activity.sessions[0]

      t = FlexiTable.new
      t.head
      t.row([ 'Lap', 'Duration', 'Distance',
              @activity.sport == 'running' ? 'Avg. Pace' : 'Avg. Speed',
              'Stride', 'Cadence', 'Avg. HR', 'Max. HR' ])
      t.set_column_attributes(Array.new(8, { :halign => :right }))
      t.body
      session.laps.each.with_index do |lap, index|
        t.cell(index + 1)
        t.cell(secsToHMS(lap.total_timer_time))
        t.cell(local_value(lap, 'total_distance', '%.2f',
                           { :metric => 'km', :statute => 'mi' }))
        if @activity.sport == 'running'
          t.cell(pace(lap, 'avg_speed', false))
        else
          t.cell(local_value(lap, 'avg_speed', '%.1f',
                             { :metric => 'km/h', :statute => 'mph' }))
        end
        t.cell(local_value(lap, 'avg_stride_length', '%.2f',
                           { :metric => 'm', :statute => 'ft' }))
        t.cell(lap.avg_running_cadence && lap.avg_fractional_cadence ?
               '%.1f' % (2 * lap.avg_running_cadence +
                         (2 * lap.avg_fractional_cadence) / 100.0) : '')
        t.cell(lap.avg_heart_rate.to_s)
        t.cell(lap.max_heart_rate.to_s)
        t.new_row
      end

      t
    end

    def hr_zones
      session = @fit_activity.sessions[0]

      t = FlexiTable.new
      t.head
      t.row([ 'Zone', 'Exertion', 'Min. HR [bpm]', 'Max. HR [bpm]',
              'Time in Zone', '% of Time in Zone' ])
      t.set_column_attributes([
        { :halign => :right },
        { :halign => :left},
        { :halign => :right },
        { :halign => :right },
        { :halign => :right },
        { :halign => :right },
      ])
      t.body

      # Calculate the total time in all the 5 relevant zones. We'll need this
      # later as the basis for the percentage values.
      total_secs = 0
      zones = gather_hr_zones

      zones.each do |zone|
        t.cell(zone.index + 1)
        t.cell([ 'Warm Up', 'Easy', 'Aerobic', 'Threshold', 'Maximum' ][zone.index])
        t.cell(zone.low)
        t.cell(zone.high)
        t.cell(secsToHMS(zone.time_in_zone))
        t.cell('%.0f%%' % zone.percent_in_zone)

        t.new_row
      end

      t
    end

    def has_hr_zones?
      # Depending on the age of the device we may have heart rate zone data
      # with zone boundaries, without zone boundaries or no data at all.
      if @fit_activity.heart_rate_zones.empty?
        # The FIT file has no heart_rate_zone records. It might have a
        # time_in_hr_zone record for the session.
        counted_zones = 0
        total_time_in_zone = 0
        each_hr_zone_with_index do |secs_in_zone, i|
          if secs_in_zone
            counted_zones += 1
            total_time_in_zone += secs_in_zone
          end
        end

        return counted_zones == 5 && total_time_in_zone > 0.0
      else
        # The FIT file has explicit heart_rate_zones records. We need the
        # session record that has type 19.
        @fit_activity.heart_rate_zones.each do |hrz|
          if hrz.type == 18 && hrz.heart_rate_zones &&
             !hrz.heart_rate_zones.empty?
            return true
          end
        end
      end
    end

    def gather_hr_zones
      zones = []

      if @fit_activity.heart_rate_zones.empty?
        # The FIT file has no heart_rate_zone records. It might have a
        # time_in_hr_zone record for the session.
        counted_zones = 0
        total_time_in_zone = 0
        each_hr_zone_with_index do |secs_in_zone, i|
          if secs_in_zone
            counted_zones += 1
            total_time_in_zone += secs_in_zone
          end
        end

        if counted_zones == 5 && total_time_in_zone > 0.0
          session = @fit_activity.sessions[0]
          hr_mins = HRZoneDetector::detect_zones(
            @fit_activity.records, session.time_in_hr_zone[0..5])
          0.upto(4) do |i|
            low = hr_mins[i + 1]
            high = i == HRZoneDetector::GARMIN_ZONES - 1 ?
              session.max_heart_rate || '-' :
              hr_mins[i + 2].nil? || hr_mins[i + 2] == 0 ? '-' :
              (hr_mins[i + 2] - 1)
            tiz = @fit_activity.sessions[0].time_in_hr_zone[i + 1]
            piz = tiz / total_time_in_zone * 100.0
            zones << HRZone.new(i, low, high, tiz, piz)
          end
        end
      else
        @fit_activity.heart_rate_zones.each do |zone|
          if zone.type == 18
            total_time = 0.0
            if zone.time_in_hr_zone
              zone.time_in_hr_zone.each { |tiz| total_time += tiz }
            end
            break if total_time <= 0.0
            if zone.heart_rate_zones
              zone.heart_rate_zones.each_with_index do |hr, i|
                break if i > 4
                zones << HRZone.new(i, hr, zone.heart_rate_zones[i + 1],
                                    zone.time_in_hr_zone[i + 1],
                                    zone.time_in_hr_zone[i + 1] /
                                    total_time * 100.0)
              end
            end
            break
          end
        end
      end

      zones
    end

    def each_hr_zone_with_index
      return unless (zones = @fit_activity.sessions[0].time_in_hr_zone)

      zones.each_with_index do |secs_in_zone, i|
        # There seems to be a zone 0 in the FIT files that isn't displayed on
        # the watch or Garmin Connect. Just ignore it.
        next if i == 0
        # There are more zones in the FIT file, but they are not displayed on
        # the watch or on the GC.
        break if i >= 6

        yield(secs_in_zone, i)
      end
    end

    def local_value(fdr, field, format, units)
      unit = units[@unit_system]
      value = fdr.get_as(field, unit)
      return '-' unless value
      "#{format % [value, unit]}"
    end

    def pace(fdr, field, show_unit = true)
      speed = fdr.get(field)
      case @unit_system
      when :metric
        "#{speedToPace(speed)}#{show_unit ? ' min/km' : ''}"
      when :statute
        "#{speedToPace(speed, 1609.34)}#{show_unit ? ' min/mi' : ''}"
      else
        Log.fatal "Unknown unit system #{@unit_system}"
      end
    end

  end

end

