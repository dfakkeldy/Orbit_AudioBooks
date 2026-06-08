require 'xcodeproj'
project_path = '/Users/dfakkeldy/Developer/Echo/Echo.xcodeproj'
project = Xcodeproj::Project.open(project_path)

def add_file(project, path, group_path, target_names)
    group = project.main_group
    group_path.split('/').each do |component|
        group = group.groups.find { |g| g.name == component || g.path == component } || group.new_group(component)
    end
    
    file_ref = group.files.find { |f| f.path == path.split('/').last || f.name == path.split('/').last }
    if file_ref.nil?
        file_ref = group.new_file(path.split('/').last)
    end

    target_names.each do |target_name|
        target = project.targets.find { |t| t.name == target_name }
        if target
            unless target.source_build_phase.files_references.include?(file_ref)
                target.source_build_phase.add_file_reference(file_ref)
                puts "Added #{path} to #{target_name}"
            end
        end
    end
end

add_file(project, 'EchoCore/Views/AudiobookPlayerUIArchitect.swift', 'EchoCore/Views', ['Echo', 'Echo macOS'])
project.save
