# frozen_string_literal: true

namespace :units do
  desc "List lab units spelled more than one way (10^3/UL, K/µL…); APPLY=1 merges each into its canonical spelling"
  task duplicates: :environment do
    groups = Units::Duplicates.groups
    puts "No duplicate units." if groups.empty?

    groups.each do |group|
      puts "#{group.name}: keep ##{group.keep.id} #{group.keep.name.inspect}, merge #{group.others.map { |u| "##{u.id} #{u.name.inspect}" }.join(", ")}"
      next unless ENV["APPLY"] == "1"

      merged = Units::MergeDuplicates.call(group)
      puts "  moved #{merged.rows} rows that named them and #{merged.ranges} ranges"
      merged.collisions.each do |range|
        puts "  left range ##{range.id} (#{range.analyte.name}, #{range.sex}) on #{range.unit.name.inspect}: #{group.name} already has one"
      end
    end
    puts "Dry run — APPLY=1 to merge." if groups.any? && ENV["APPLY"] != "1"
  end
end
