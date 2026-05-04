require 'xcodeproj'

project_path = 'BookLoop.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Find the watch app target and widget target
watch_target = project.targets.find { |t| t.name == 'BookLoop Watch App Watch App' }
widget_target = project.targets.find { |t| t.name == 'BookLoop WidgetExtension' }

if watch_target
  watch_target.build_configurations.each do |config|
    config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'BookLoop.entitlements'
  end
  puts "Added entitlements to Watch App"
end

if widget_target
  widget_target.build_configurations.each do |config|
    config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'BookLoop.entitlements'
  end
  puts "Added entitlements to Widget Extension"
end

project.save
puts "Project saved"
