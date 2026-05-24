require 'xcodeproj'

project_path = 'VoltaicVelocity.xcodeproj'
project = Xcodeproj::Project.open(project_path)

url = 'https://github.com/gonzalezreal/swift-markdown-ui'

pkg_ref = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
pkg_ref.repositoryURL = url
pkg_ref.requirement = {
  "kind" => "upToNextMajorVersion",
  "minimumVersion" => "2.4.0"
}
project.root_object.package_references << pkg_ref

target = project.targets.find { |t| t.name == 'VoltaicVelocity' }

pkg_dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
pkg_dep.package = pkg_ref
pkg_dep.product_name = 'MarkdownUI'

target.package_product_dependencies << pkg_dep

frameworks_phase = target.frameworks_build_phase
build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
build_file.product_ref = pkg_dep
frameworks_phase.files << build_file

project.save
puts "Successfully added MarkdownUI to #{project_path}"
