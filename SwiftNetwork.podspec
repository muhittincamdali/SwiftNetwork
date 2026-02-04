Pod::Spec.new do |s|
  s.name             = 'SwiftNetwork'
  s.version          = '1.0.0'
  s.summary          = 'Modern networking library with async/await and Combine support.'
  s.description      = 'SwiftNetwork provides modern networking with async/await, Combine, and comprehensive error handling.'
  s.homepage         = 'https://github.com/muhittincamdali/SwiftNetwork'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Muhittin Camdali' => 'contact@muhittincamdali.com' }
  s.source           = { :git => 'https://github.com/muhittincamdali/SwiftNetwork.git', :tag => s.version.to_s }
  s.ios.deployment_target = '15.0'
  s.swift_versions = ['5.9', '5.10', '6.0']
  s.source_files = 'Sources/**/*.swift'
  s.frameworks = 'Foundation', 'Combine'
end
