set(CMAKE_SYSTEM_NAME Generic)
set(AS_INT_APP_TYPE "RTApp" CACHE INTERNAL "Type of application (\"HLApp\" or \"RTApp\")")

# Get sdk and cmake dir from environment set from toolchain location
set(AZURE_SPHERE_CMAKE_PATH ${CMAKE_CURRENT_LIST_DIR})
string(FIND ${AZURE_SPHERE_CMAKE_PATH} "/" AZURE_SPHERE_SDK_PATH_END REVERSE)
string(SUBSTRING ${AZURE_SPHERE_CMAKE_PATH} 0 ${AZURE_SPHERE_SDK_PATH_END} AZURE_SPHERE_SDK_PATH)
set(ENV{AzureSphereCMakePath} ${AZURE_SPHERE_CMAKE_PATH})
set(ENV{AzureSphereSDKPath} ${AZURE_SPHERE_SDK_PATH})
set(AZURE_SPHERE_CMAKE_PATH $ENV{AzureSphereCMakePath})
set(AZURE_SPHERE_SDK_PATH $ENV{AzureSphereSDKPath} CACHE INTERNAL "Path to the Azure Sphere SDK")

# Execute common tasks
include ("${AZURE_SPHERE_CMAKE_PATH}/AzureSphereToolchainBase.cmake")