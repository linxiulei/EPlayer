use_frameworks!
platform :ios, '10.3'

target 'EPlayer' do
    pod 'AlamofireXMLRPC', :git => 'https://github.com/kodlian/AlamofireXMLRPC.git'
    pod 'GzipSwift'
    pod 'BEMCheckBox'
end

# Workaround for Cocoapods issue #7606
post_install do |installer|
    installer.pods_project.build_configurations.each do |config|
        config.build_settings.delete('CODE_SIGNING_ALLOWED')
        config.build_settings.delete('CODE_SIGNING_REQUIRED')
    end
end
