Pod::Spec.new do |s|
  s.name             = 'flutter_native_3d'
  s.version          = '0.1.0'
  s.summary          = 'Native 3D model rendering for Flutter.'
  s.description      = 'A Flutter plugin for rendering 3D models natively using SceneKit on iOS.'
  s.homepage         = 'https://github.com/user/flutter_native_3d'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'Author' => 'author@example.com' }
  s.source           = { :http => 'https://github.com/user/flutter_native_3d' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.dependency 'GLTFKit2', '~> 0.3'
  s.platform         = :ios, '15.0'
  s.swift_version    = '5.9'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
