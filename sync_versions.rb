require 'xcodeproj'

project_path = 'BookLoop.xcodeproj'
project = Xcodeproj::Project.open(project_path)

project.targets.each do |target|
  target.build_configurations.each do |config|
    config.build_settings['CURRENT_PROJECT_VERSION'] = '6'
    config.build_settings['MARKETING_VERSION'] = '1.0.2'
  end
end

project.save
puts "Project versions synced to 6 / 1.0.2"
