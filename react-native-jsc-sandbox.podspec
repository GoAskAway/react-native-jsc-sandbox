require 'json'

package = JSON.parse(File.read(File.join(__dir__, 'package.json')))

Pod::Spec.new do |s|
  s.name         = "react-native-jsc-sandbox"
  s.version      = package['version']
  s.summary      = package['description']
  s.homepage     = "https://github.com/GoAskAway/react-native-jsc-sandbox"
  s.license      = { :type => "Apache-2.0", :file => "LICENSE" }
  s.authors      = { "GoAskAway" => "https://github.com/GoAskAway" }

  # All Apple platforms where JavaScriptCore is available
  s.ios.deployment_target = "13.0"
  s.osx.deployment_target = "10.15"
  s.tvos.deployment_target = "13.0"

  s.source       = { :git => "https://github.com/GoAskAway/react-native-jsc-sandbox.git", :tag => "v#{s.version}" }
  s.source_files = "darwin/**/*.{h,mm}"
  s.public_header_files = "darwin/**/*.h"

  # C++ settings for JSI
  s.pod_target_xcconfig = {
    "CLANG_CXX_LANGUAGE_STANDARD" => "c++17",
    "DEFINES_MODULE" => "YES"
  }

  # JavaScriptCore is a system framework on all Apple platforms
  s.frameworks = "JavaScriptCore"

  # React Native dependencies for JSI and TurboModules
  s.dependency "React-Core"
  s.dependency "React-jsi"
  s.dependency "React-NativeModulesApple"
  s.dependency "ReactCommon/turbomodule/core"
end
