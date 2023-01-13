# Check generator is selected as Ninja in CMakePresets.json file
if(NOT ${CMAKE_GENERATOR} STREQUAL "Ninja")
    message(FATAL_ERROR "Azure Sphere CMake projects must use the Ninja generator")
endif()

# Force CMake to generate paths with forward slashes to work around response file generation errors
set(CMAKE_COMPILER_IS_MINGW 1)

# ? DHEBUG - is this still needed and should it be defined
# ?  The function code is in AzureSphereInternal.cmake line 149
set(AZURE_SPHERE_MAKE_IMAGE_FILE "${AZURE_SPHERE_CMAKE_PATH}/AzureSphereMakeImage.cmake" CACHE INTERNAL "Path to the MakeImage CMake target")

# List of SDKs 
#? Do we need to remote the older ones?
set(sdks_2004_or_later "20.04" "20.07" "20.10" "20.11" "21.01" "21.02" "21.04" "21.07" "21.10" "22.02" "22.07" "22.09" "22.11")

# Sysroots 8 and 9 don't contain libmalloc
set(libmalloc_10_or_later "10" "11" "12" "13" "14" "15")

# Set Azure sphere approot directory
set(AZURE_SPHERE_APPROOT_DIR "${CMAKE_BINARY_DIR}/approot${PROJECT_NAME}")

# Get available and installed API sets
file(GLOB AZURE_SPHERE_AVAILABLE_API_SETS RELATIVE "${AZURE_SPHERE_SDK_PATH}/Sysroots" "${AZURE_SPHERE_SDK_PATH}/Sysroots/*")

# Check if AS_INT_RESOLVED_API_SET variable has been set
if (NOT (DEFINED AS_INT_RESOLVED_API_SET))
    #_azsphere_get_selected_api_set()

    #_get_actual_latest_lts
    set (lts_api_sets ${AZURE_SPHERE_AVAILABLE_API_SETS})
    list (FILTER lts_api_sets INCLUDE REGEX "^[0-9]+$")
    set (highest_lts_api_set -1)
    foreach(api_set ${lts_api_sets})
        if (${api_set} GREATER ${highest_lts_api_set})
            set(highest_lts_api_set ${api_set})
        endif()
    endforeach()

    set (AS_INT_ACTUAL_LATEST_LTS "${highest_lts_api_set}" CACHE INTERNAL "API set corresponding to latest-lts.")
    # endfunction () #_get_actual_latest_lts

    #_get_actual_latest_beta
    set(beta_api_sets ${AZURE_SPHERE_AVAILABLE_API_SETS})
    list(FILTER beta_api_sets INCLUDE REGEX "^[0-9]+\\+Beta[0-9]+$")
    set (highest_beta_arv -1)
    set (highest_beta_release -1)
    foreach(api_set ${beta_api_sets})
        string(REGEX REPLACE "^([0-9]+)\\+Beta([0-9]+)$" "\\1" arv_part "${api_set}")
        string(REGEX REPLACE "^([0-9]+)\\+Beta([0-9]+)$" "\\2" release_part "${api_set}")
        
        if (${arv_part} GREATER ${highest_beta_arv})
            set (highest_beta_arv ${arv_part})
            set(highest_beta_release ${release_part})
        elseif(${arv_part} EQUAL ${highest_beta_arv}) AND (${release_part} GREATER ${highest_beta_release})
            set(highest_beta_release ${release_part})  
        endif()
    endforeach()

    set(AS_INT_ACTUAL_LATEST_BETA "${highest_beta_arv}+Beta${highest_beta_release}" CACHE INTERNAL "API set corresponding to latest-beta")
    #endfunction() #_get_actual_latest_beta
        
    # Fallback - API set is set in environment variable.  This includes the "AzureSphere"
    # environment in Visual Studio CMakeSettings.json.
    if(DEFINED ENV{AzureSphereTargetApiSet})
        set(logical_api_set $ENV{AzureSphereTargetApiSet})
    endif ()

    # 20.01 - If the user has set the AZURE_SPHERE_TARGET_API_SET variable, use that.
    if (DEFINED AZURE_SPHERE_TARGET_API_SET)
        set(logical_api_set ${AZURE_SPHERE_TARGET_API_SET})
    endif()

    # If the user has defined neither ENV{AzureSphereTargetApiSet} nor AZURE_SPHERE_TARGET_API_SET,
    # then default to latest-lts.  Record the fact that defaulted, because this is only supported with
    # SDK 20.04 or later.  If the user does not opt into 20.04 or later by calling azsphere_configure_tools,
    # the generation will fail with an error when the image package rules are added.
    # From SDK 20.07, real-time capable applications should not take a target API set.
    if ("${AS_INT_APP_TYPE}" STREQUAL "RTApp")
        if (DEFINED logical_api_set)
            message(
                WARNING
                "Real-time capable applications do not require a target API set. "
                "The value of AZURE_SPHERE_TARGET_API_SET will be ignored.")
        endif()
        set (AS_INT_RESOLVED_API_SET "ignored-for-rtapp" CACHE INTERNAL "API set used to build the applicaiton.")
    
    else()
        if (DEFINED logical_api_set)
            set (AS_INT_USER_API_SET "${logical_api_set}" CACHE INTERNAL "API set explicitly requested by user")
        else()
            set (AS_INT_IMPLICIT_LATEST_LTS "ON" CACHE INTERNAL "Whether defaulted to latest-lts because no API set was specified"
            set(logical_api_set "latest-lts"))
        endif()
    endif()

    # _azsphere_resolve_api_set("${logical_api_set}")
    if ("${logical_api_set}" STREQUAL "latest-lts")
        message(STATUS "Auto-selected latest LTS API set \"${AS_INT_ACTUAL_LATEST_LTS}\"")
        set(ARAS_RESOLVED_API_SET "${AS_INT_ACTUAL_LATEST_LTS}") # PARENT_SCOPE)
    elseif ("${logical_api_set}" STREQUAL "latest-beta")
        message(STATUS "Auto-selected latest Beta API set \"${AS_INT_ACTUAL_LATEST_BETA}\"")
        set(ARAS_RESOLVED_API_SET "${AS_INT_ACTUAL_LATEST_BETA}") # PARENT_SCOPE)
    else()
        # Neither "latest-lts" nor "latest-beta", so interpret literally.
        set(ARAS_RESOLVED_API_SET "${logical_api_set}") # PARENT_SCOPE)
    endif()
    # endfunction() #_azsphere_resolve_api_set("${logical_api_set}")

    set (AS_INT_RESOLVED_API_SET "${ARAS_RESOLVED_API_SET}" CACHE INTERNAL "API set used to build the application")

    # endfunction() #_azsphere_get_selected_api_set
endif()

if (NOT ("${AS_INT_RESOLVED_API_SET}" STREQUAL "ignored-for-rtapp"))
    # Set include pats and check if given api set is valid
    set (AZURE_SPHERE_API_SET_VALID 0)
    foreach(AZURE_SPHRE_API_SET ${AZURE_SPHERE_AVAILABLE_API_SETS})
        set (ENV{INCLUDE} "${AZURE_SPHERE_SDK_PATH}/Sysroots/${AZURE_SPHRE_API_SET}/usr/include;$ENV{INCLUDE}")
        if ("${AS_INT_RESOLVED_API_SET}" STREQUAL "${AZURE_SPHRE_API_SET}")
            set (AZURE_SPHERE_API_SET_VALID 1)
        endif()        
    endforeach()

    if (NOT AZURE_SPHERE_API_SET_VALID)
        # Create API set list
        set (AZURE_SPHERE_API_SET_LIST "['${AZURE_SPHERE_AVAILABLE_API_SETS}']")
        string(REPLACE ";" "', '" AZURE_SPHERE_API_SET_LIST "${AZURE_SPHERE_API_SET_LIST}")
        message( FATAL_ERROR
            "Target API set '${AS_INT_RESOLVED_API_SET}' is not supported by this SDK. "
            "Please update your SDK at http://aka.ms/AzureSphereSDKDownload. "
            "Supported API sets are ${AZURE_SPHERE_API_SET_LIST}. For 20.04 or later projects, "
            "'latest-lts' and 'latest-beta' can also be specified."
        )
    endif()
endif()

set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# Get hardware definition directory
if(DEFINED AZURE_SPHERE_TARGET_HARDWARE_DEFINITION_DIRECTORY)
    if (IS_ABSOLUTE "${AZURE_SPHERE_TARGET_HARDWARE_DEFINITION_DIRECTORY}")
        set(ENV{AzureSphereTargetHardwareDefinitionDirectory} ${AZURE_SPHERE_TARGET_HARDWARE_DEFINITION_DIRECTORY})
    else()
        get_filename_component(AZURE_SPHERE_TARGET_HARDWARE_DEFINITION_DIRECTORY_ABS ${AZURE_SPHERE_TARGET_HARDWARE_DEFINITION_DIRECTORY} ABSOLUTE BASE_DIR ${CMAKE_SOURCE_DIR})
        set(ENV{AzureSphereTargetHardwareDefinitionDirectory} ${AZURE_SPHERE_TARGET_HARDWARE_DEFINITION_DIRECTORY_ABS})
    endif()
endif()
set(AZURE_SPHERE_HW_DIRECTORY $ENV{AzureSphereTargetHardwareDefinitionDirectory})

# Get hardware definition json
if(DEFINED AZURE_SPHERE_TARGET_HARDWARE_DEFINITION)
    set(ENV{AzureSphereTargetHardwareDefinition} ${AZURE_SPHERE_TARGET_HARDWARE_DEFINITION})
endif()
set(AZURE_SPHERE_HW_DEFINITION $ENV{AzureSphereTargetHardwareDefinition})

# Check if the hardware definition file exists at the specified path
if((NOT ("${AZURE_SPHERE_HW_DEFINITION}" STREQUAL "")) AND (NOT ("${AZURE_SPHERE_HW_DIRECTORY}" STREQUAL "")))
    set(GENERIC_HW_MESSAGE_ERROR "The target hardware is not valid. To resolve this, you'll need to update the CMake build. The necessary steps vary depending on if you are building in Visual Studio, in Visual Studio Code or via the command line. See https://aka.ms/AzureSphereHardwareDefinitions for more details. ")
    if(NOT EXISTS "${AZURE_SPHERE_HW_DIRECTORY}/${AZURE_SPHERE_HW_DEFINITION}")
        message(FATAL_ERROR "${AZURE_SPHERE_HW_DIRECTORY}/${AZURE_SPHERE_HW_DEFINITION} does not exist. ${GENERIC_HW_MESSAGE_ERROR}")
    elseif(EXISTS "${AZURE_SPHERE_HW_DIRECTORY}/${AZURE_SPHERE_HW_DEFINITION}" AND IS_DIRECTORY "${AZURE_SPHERE_HW_DIRECTORY}/${AZURE_SPHERE_HW_DEFINITION}")
        message(FATAL_ERROR "${AZURE_SPHERE_HW_DIRECTORY}/${AZURE_SPHERE_HW_DEFINITION} is a directory, not a .json file. ${GENERIC_HW_MESSAGE_ERROR}")
    endif()
endif()

# Disable linking during try_compile since our link options cause the generation to fail
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY CACHE INTERNAL "Disable linking for try_compile")

# Add ComponentId to app_manifest if necessary
if(EXISTS "${CMAKE_SOURCE_DIR}/app_manifest.json")
    file(READ "${CMAKE_SOURCE_DIR}/app_manifest.json" AZURE_SPHERE_APP_MANIFEST_CONTENTS)
    string(REGEX MATCH "\"ComponentId\": \"([^\"]*)\"" AZURE_SPHERE_COMPONENTID "${AZURE_SPHERE_APP_MANIFEST_CONTENTS}")
    set(AZURE_SPHERE_COMPONENTID_VALUE "${CMAKE_MATCH_1}")
    # CMake Regex doesn't support syntax for matching exact number of characters, so we get to do guid matching the fun way
    set(AZURE_SPHERE_GUID_REGEX "[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]")
    set(AZURE_SPHERE_GUID_REGEX_2 "[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]")
    set(AZURE_SPHERE_GUID_REGEX_3 "[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]")
    set(AZURE_SPHERE_GUID_REGEX_4 "[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]")
    set(AZURE_SPHERE_GUID_REGEX_5 "[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]")
    string(APPEND AZURE_SPHERE_GUID_REGEX "-" ${AZURE_SPHERE_GUID_REGEX_2} "-" ${AZURE_SPHERE_GUID_REGEX_3} "-" ${AZURE_SPHERE_GUID_REGEX_4} "-" ${AZURE_SPHERE_GUID_REGEX_5})
    string(REGEX MATCH "${AZURE_SPHERE_GUID_REGEX}" AZURE_SPHERE_COMPONENTID_GUID "${AZURE_SPHERE_COMPONENTID_VALUE}")
    if("${AZURE_SPHERE_COMPONENTID_GUID}" STREQUAL "")
        # Generate random GUID
        string(RANDOM LENGTH 8 ALPHABET "0123456789abcdef" AZURE_SPHERE_GUID)
        string(RANDOM LENGTH 4 ALPHABET "0123456789abcdef" AZURE_SPHERE_GUID_2)
        string(RANDOM LENGTH 4 ALPHABET "0123456789abcdef" AZURE_SPHERE_GUID_3)
        string(RANDOM LENGTH 4 ALPHABET "0123456789abcdef" AZURE_SPHERE_GUID_4)
        string(RANDOM LENGTH 12 ALPHABET "0123456789abcdef" AZURE_SPHERE_GUID_5)
        string(APPEND AZURE_SPHERE_GUID "-" ${AZURE_SPHERE_GUID_2} "-" ${AZURE_SPHERE_GUID_3} "-" ${AZURE_SPHERE_GUID_4} "-" ${AZURE_SPHERE_GUID_5})
        # Write GUID to ComponentId
        string(REGEX REPLACE "\"ComponentId\": \"[^\"]*\"" "\"ComponentId\": \"${AZURE_SPHERE_GUID}\"" AZURE_SPHERE_APP_MANIFEST_CONTENTS "${AZURE_SPHERE_APP_MANIFEST_CONTENTS}")
        file(WRITE "${CMAKE_SOURCE_DIR}/app_manifest.json" ${AZURE_SPHERE_APP_MANIFEST_CONTENTS})
    endif()
endif()

if (DEFINED AZURE_SPHERE_LTO)
    if(${CMAKE_HOST_WIN32})
        set(STATIC_LIBRARY_OPTIONS "--plugin liblto_plugin-0.dll")
    else()
        set(STATIC_LIBRARY_OPTIONS "--plugin liblto_plugin-0")
    endif()
    add_compile_options(-flto)
    add_link_options(-flto)
endif()


# Set the cache variables based on the toolchain for MT3620
function (_set_tool_chain_mt3620)
            
    set(AZURE_SPHERE_API_SET_DIR "${AZURE_SPHERE_SDK_PATH}/Sysroots/${AS_INT_RESOLVED_API_SET}" CACHE INTERNAL "Path to the selected API set in the Azure Sphere SDK")
    set(CMAKE_FIND_ROOT_PATH "${AZURE_SPHERE_API_SET_DIR}")

    # Set up compiler and flags
    if(${CMAKE_HOST_WIN32})
        set(GCC_ROOT_DIR "${AZURE_SPHERE_API_SET_DIR}/tools/gcc")
        set(CMAKE_C_COMPILER "${GCC_ROOT_DIR}/arm-poky-linux-musleabi-gcc.exe" CACHE INTERNAL "Path to the C compiler in the selected API set targeting High-Level core")
        set(CMAKE_CXX_COMPILER "${GCC_ROOT_DIR}/arm-poky-linux-musleabi-g++.exe" CACHE INTERNAL "Path to the C++ compiler in the selected API set targeting High-Level core")
        set(CMAKE_AR "${GCC_ROOT_DIR}/arm-poky-linux-musleabi-ar.exe" CACHE INTERNAL "Path to the archiver in the selected API set targeting High-Level core")

        set(ENV{PATH} "${AZURE_SPHERE_SDK_PATH}/Tools;${GCC_ROOT_DIR};$ENV{PATH}")

        # Set CPath to tell compiler the default include path, workaround for bad default include path in compiler
        set(ENV{CPATH} "${AZURE_SPHERE_API_SET_DIR}/usr/include;$ENV{CPATH}")
    else()
        set(GCC_ROOT_DIR "${AZURE_SPHERE_API_SET_DIR}/tools/sysroots/x86_64-pokysdk-linux/usr/bin/arm-poky-linux-musleabi")
        set(CMAKE_C_COMPILER "${GCC_ROOT_DIR}/arm-poky-linux-musleabi-gcc" CACHE INTERNAL "Path to the C compiler in the selected API set targeting High-Level core")
        set(CMAKE_CXX_COMPILER "${GCC_ROOT_DIR}/arm-poky-linux-musleabi-g++" CACHE INTERNAL "Path to the C++ compiler in the selected API set targeting High-Level core")
        set(CMAKE_AR "${GCC_ROOT_DIR}/arm-poky-linux-musleabi-ar" CACHE INTERNAL "Path to the archiver in the selected API set targeting High-Level core")
        set(CMAKE_STRIP "${GCC_ROOT_DIR}/arm-poky-linux-musleabi-strip" CACHE INTERNAL "Path to the strip tool in the selected API set targeting High-Level core")

        set(ENV{PATH} "${AZURE_SPHERE_SDK_PATH}/Tools:${GCC_ROOT_DIR}:$ENV{PATH}")

        # Set CPath to tell compiler the default include path, workaround for bad default include path in compiler
        set(ENV{CPATH} "${AZURE_SPHERE_API_SET_DIR}/usr/include:$ENV{CPATH}")
    endif()

    set(CMAKE_C_FLAGS_INIT "-B \"${GCC_ROOT_DIR}\" -march=armv7ve -mthumb -mfpu=neon-vfpv4 -mfloat-abi=hard \
    -mcpu=cortex-a7 --sysroot=\"${AZURE_SPHERE_API_SET_DIR}\"")
    set(CMAKE_CXX_FLAGS_INIT "-B \"${GCC_ROOT_DIR}\" -march=armv7ve -mthumb -mfpu=neon-vfpv4 -mfloat-abi=hard \
    -mcpu=cortex-a7 --sysroot=\"${AZURE_SPHERE_API_SET_DIR}\"")
    set(CMAKE_EXE_LINKER_FLAGS_INIT "-nodefaultlibs -pie -Wl,--no-undefined -Wl,--gc-sections")

    set(CMAKE_C_STANDARD_INCLUDE_DIRECTORIES "${AZURE_SPHERE_API_SET_DIR}/usr/include")
    set(CMAKE_CXX_STANDARD_INCLUDE_DIRECTORIES "${AZURE_SPHERE_API_SET_DIR}/usr/include")

    # Append the hardware definition directory
    if((NOT ("${AZURE_SPHERE_HW_DEFINITION}" STREQUAL "")) AND (IS_DIRECTORY "${AZURE_SPHERE_HW_DIRECTORY}/inc"))
        list(APPEND CMAKE_C_STANDARD_INCLUDE_DIRECTORIES "${AZURE_SPHERE_HW_DIRECTORY}/inc")
        list(APPEND CMAKE_CXX_STANDARD_INCLUDE_DIRECTORIES "${AZURE_SPHERE_HW_DIRECTORY}/inc")
    endif()

    add_definitions(-D_POSIX_C_SOURCE)
    set(COMPILE_DEBUG_FLAGS $<$<CONFIG:Debug>:-ggdb> $<$<CONFIG:Debug>:-O0>)
    set(COMPILE_RELEASE_FLAGS $<$<CONFIG:Release>:-g1> $<$<CONFIG:Release>:-Os>)
    set(COMPILE_C_FLAGS $<$<COMPILE_LANGUAGE:C>:-std=c11> $<$<COMPILE_LANGUAGE:C>:-Wstrict-prototypes> $<$<COMPILE_LANGUAGE:C>:-Wno-pointer-sign>)
    add_compile_options(${COMPILE_C_FLAGS} ${COMPILE_DEBUG_FLAGS} ${COMPILE_RELEASE_FLAGS} -fPIC
                        -ffunction-sections -fdata-sections -fno-strict-aliasing
                        -fno-omit-frame-pointer -fno-exceptions -Wall
                        -Wswitch -Wempty-body -Wconversion -Wreturn-type -Wparentheses
                        -Wno-format -Wuninitialized -Wunreachable-code
                        -Wunused-function -Wunused-value -Wunused-variable
                        -Werror=implicit-function-declaration -fstack-protector-strong)

endfunction()

function(azsphere_configure_tools)
    set(options)
    set(oneValueArgs TOOLS_REVISION)
    set(multiValueArgs)
    cmake_parse_arguments(ACS "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    if (NOT (DEFINED ACS_TOOLS_REVISION))
        message(FATAL_ERROR "azsphere_configure_tools requires TOOLS_REVISION argument")
    elseif(DEFINED ACS_UNPARSED_ARGUMENTS)
        message(FATAL_ERROR "azsphere_configure_tools received unexpected argument(s) ${ACS_UNPARSED_ARGUMENTS}")
    endif()

    if ("${ACS_TOOLS_REVISION}" IN_LIST sdks_2004_or_later)
        # Ensure pre-20.04 arguments are not supplied on the command line.
        if (DEFINED AZURE_SPHERE_TARGET_HARDWARE_DEFINITION_DIRECTORY)
            message(FATAL_ERROR
                "azsphere_configure_tools: Do not specify the external variable "
                "AZURE_SPHERE_TARGET_HARDWARE_DEFINITION_DIRECTORY if using tools revision 20.04 or later. "
                "See https://aka.ms/AzureSphereToolsRevisions and https://aka.ms/AzureSphereHardwareDefinitions.")
        endif()
        if (DEFINED AZURE_SPHERE_TARGET_HARDWARE_DEFINITION)
            message(FATAL_ERROR
                "azsphere_configure_tools: Do not specify the external variable "
                "AZURE_SPHERE_TARGET_HARDWARE_DEFINITION if using tools revision 20.04 or later. "
                "See https://aka.ms/AzureSphereToolsRevisions and https://aka.ms/AzureSphereHardwareDefinitions.")
        endif()
    else()
        string(REPLACE ";" "', '" supported_tools_revisions_txt "['${sdks_2004_or_later}']")
        message(FATAL_ERROR
            "azsphere_configure_tools: unsupported tools version \"${ACS_TOOLS_REVISION}\". "
            "Only ${sdks_2004_or_later} are supported.")
    endif()

    set(AS_INT_SELECTED_TOOLS "${ACS_TOOLS_REVISION}" CACHE INTERNAL "Tools version configured from CMakeLists.txt")
endfunction()


