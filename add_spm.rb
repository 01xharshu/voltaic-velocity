require 'xcodeproj'

project_path = 'VoltaicVelocity.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# SPM package URL and version requirements
url = 'https://github.com/gonzalezreal/swift-markdown-ui'
version_req = Xcodeproj::Project::Object::XCRemoteSwiftPackageReference::VersionRequirement.up_to_next_major('2.4.0')

# Create the package reference
pkg_ref = project.root_object.add_swift_package_reference(url, version_req)

# Find target
target = project.targets.first

# Add to the target's package product dependencies
pkg_dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
pkg_dep.package = pkg_ref
pkg_dep.product_name = 'MarkdownUI'

# Add dependency to target
target.package_product_dependencies << pkg_dep

# We also need to add it to the frameworks build phase
# (xcodeproj doesn't automatically link SPM products, we have to add a build file for it)
frameworks_phase = target.frameworks_build_phase
build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
build_file.product_ref = pkg_dep
frameworks_phase.files << build_file

project.save
puts "Successfully added MarkdownUI to #{project_path}"
