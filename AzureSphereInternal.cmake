function(_azsphere_add_manifest_dependency app_manifest_fn)
    # Remove previous approot when CMakeLists.txt changes because the latter
    # describes what resource files are placed in the former.
    # It will be recreated when the application is built.
    file(REMOVE_RECURSE "${AZURE_SPHERE_APPROOT_DIR}")

    add_custom_command(OUTPUT "${AZURE_SPHERE_APPROOT_DIR}/app_manifest.json"
        COMMAND ${CMAKE_COMMAND} -E make_directory "${AZURE_SPHERE_APPROOT_DIR}"

        DEPENDS "${CMAKE_SOURCE_DIR}/app_manifest.json" "${CMAKE_BINARY_DIR}/${PROJECT_NAME}.out")
endfunction()

function(_azsphere_copy_resource_files_into_approot)
    get_target_property(res_files ${PROJECT_NAME} AS_RESOURCE_FILES)
    get_target_property(debug_file ${PROJECT_NAME} AS_DEBUG_LIB)
    if(NOT ("${debug_file}" STREQUAL ""))
        configure_file("${debug_file}" "${AZURE_SPHERE_APPROOT_DIR}/libmalloc.so.0" COPYONLY)
    endif()
    foreach(res_file ${res_files})
        string(REPLACE "\\" "/" res_file_fwd_slash ${res_file})
        string(FIND ${res_file_fwd_slash} "/" res_file_last_fwd_slash REVERSE)

        if(NOT ${res_file_last_fwd_slash} EQUAL -1)
            # Get directory leading up to source resource file
            string(SUBSTRING ${res_file_fwd_slash} 0 ${res_file_last_fwd_slash} res_file_src_dir)
            add_custom_command(OUTPUT "${AZURE_SPHERE_APPROOT_DIR}/${res_file}"
                COMMAND ${CMAKE_COMMAND} -E make_directory "${AZURE_SPHERE_APPROOT_DIR}/${res_file_src_dir}"
                COMMAND ${CMAKE_COMMAND} -E copy "${CMAKE_SOURCE_DIR}/${res_file_fwd_slash}" "${AZURE_SPHERE_APPROOT_DIR}/${res_file_fwd_slash}"
                DEPENDS "${CMAKE_SOURCE_DIR}/${res_file_fwd_slash}")
        else()
            add_custom_command(OUTPUT "${AZURE_SPHERE_APPROOT_DIR}/${res_file}"
                COMMAND ${CMAKE_COMMAND} -E make_directory "${AZURE_SPHERE_APPROOT_DIR}"
                COMMAND ${CMAKE_COMMAND} -E copy "${CMAKE_SOURCE_DIR}/${res_file_fwd_slash}" "${AZURE_SPHERE_APPROOT_DIR}/${res_file_fwd_slash}"
                DEPENDS "${CMAKE_SOURCE_DIR}/${res_file_fwd_slash}")
        endif()
    endforeach()
endfunction()

function(_azsphere_copy_executable_into_approot)
    add_custom_command(OUTPUT "${AZURE_SPHERE_APPROOT_DIR}/bin/app"
        COMMAND ${CMAKE_COMMAND} -E make_directory "${AZURE_SPHERE_APPROOT_DIR}/bin"
        COMMAND ${CMAKE_COMMAND} -E copy "${CMAKE_BINARY_DIR}/${PROJECT_NAME}.out" "${AZURE_SPHERE_APPROOT_DIR}/bin/app"
        COMMAND "${CMAKE_STRIP}" --strip-unneeded "${AZURE_SPHERE_APPROOT_DIR}/bin/app"
        DEPENDS "${CMAKE_BINARY_DIR}/${PROJECT_NAME}.out")
endfunction()

function(_azsphere_target_add_image_package_common target)
    # If the API set was chosen implicitly, fail here unless SDK 20.04 or later was selected.
    # This is not an obvious place to perform the check, but it may be the only time that
    # CMakeLists.txt calls into the toolchain.

    set(implicit_lts_tools_revisions "${sdks_2004_or_later}")
    if ((DEFINED AS_INT_IMPLICIT_LATEST_LTS) AND (NOT ("${AS_INT_SELECTED_TOOLS}" IN_LIST implicit_lts_tools_revisions)))
        message(
            FATAL_ERROR
            "Did not supply a target API set with AZURE_SPHERE_TARGET_API_SET. "
            "Either supply a target API set, or use tools revision 20.04 or later "
            "to enable selecting latest LTS API set by default. "
            "See https://aka.ms/AzureSphereToolsRevisions.")
    endif()

    set(latest_lts_tools_revisions "${sdks_2004_or_later}")
    set(logical_latest "latest-lts" "latest-beta")
    if (("${AS_INT_USER_API_SET}" IN_LIST logical_latest) AND (NOT ("${AS_INT_SELECTED_TOOLS}" IN_LIST latest_lts_tools_revisions)))
        message(
            FATAL_ERROR
            "Cannot set the AZURE_SPHERE_TARGET_API_SET parameter to \"latest-lts\" or \"latest-beta\" "
            "when using the deprecated Azure Sphere tools revision 20.01 or earlier. "
            "See https://aka.ms/AzureSphereToolsRevisions.")
    endif()

    # Warn if using legacy (20.01) project format.
    if("${AS_INT_SELECTED_TOOLS}" STREQUAL "")
        message(
            WARNING
            "This app uses the deprecated Azure Sphere tools revision 20.01 or earlier. "
            "See https://aka.ms/AzureSphereToolsRevisions.")
    endif()

    # If the user called azsphere_configure_tools but did not call azsphere_configure_api, and not building
    # a real-time capable application, then print a fatal error message.
    if (    (DEFINED AS_INT_SELECTED_TOOLS)
        AND (NOT (DEFINED AS_INT_CONFIGURED_API_SET))
        AND (NOT ("${AS_INT_APP_TYPE}" STREQUAL "RTApp")) )
        message(
            FATAL_ERROR
            "The target API set was not configured. Call azsphere_configure_api(TARGET_API_SET <target value>). "
            "See https://aka.ms/AzureSphereToolsRevisions.")
    endif()

    set(options)
    set(oneValueArgs APP_MANIFEST DEBUG_LIB)
    set(multiValueArgs RESOURCE_FILES)
    cmake_parse_arguments(PARSE_ARGV 1 ATAIPC "${options}" "${oneValueArgs}" "${multiValueArgs}")

    set_target_properties(${target} PROPERTIES AS_RESOURCE_FILES "${ATAIPC_RESOURCE_FILES}")
    set_target_properties(${target} PROPERTIES AS_DEBUG_LIB "${ATAIPC_DEBUG_LIB}")

    # Force executable to have .out extension for debugging to work
    # This is a requirement of Open Folder infrastructure in Visual Studio
    set_target_properties(${PROJECT_NAME} PROPERTIES OUTPUT_NAME "${PROJECT_NAME}.out")

    # Arguments for the image-package command
    set(AZURE_SPHERE_PACKAGE_COMMAND_ARG "--verbose")

    _azsphere_add_manifest_dependency($ATAIPC_APP_MANIFEST)
    list(APPEND AZURE_SPHERE_PACKAGE_COMMAND_ARG "--application-manifest;${ATAIPC_APP_MANIFEST}")

    _azsphere_copy_resource_files_into_approot()
    _azsphere_copy_executable_into_approot()

    list(APPEND AZURE_SPHERE_PACKAGE_COMMAND_ARG "--package-directory;${AZURE_SPHERE_APPROOT_DIR}")
    list(APPEND AZURE_SPHERE_PACKAGE_COMMAND_ARG "--destination;${CMAKE_BINARY_DIR}/${PROJECT_NAME}.imagepackage")

    # Target API set should not be specified for real-time capable applications.
    if (NOT ("${AS_INT_RESOLVED_API_SET}" STREQUAL "ignored-for-rtapp"))
        list(APPEND AZURE_SPHERE_PACKAGE_COMMAND_ARG "--target-api-set;\"${AS_INT_RESOLVED_API_SET}\"")
    endif()

    # If the user has selected a hardware definition by calling azsphere_target_set_hardware_definition
    # then use the project-specific property which was set there.  Otherwise, use the command-line arguments.
    get_target_property(pkg_hwd_args ${PROJECT_NAME} AS_PKG_HWD_ARGS)
    if (NOT("${pkg_hwd_args}" STREQUAL "pkg_hwd_args-NOTFOUND"))
        list(APPEND AZURE_SPHERE_PACKAGE_COMMAND_ARG "${pkg_hwd_args}")
    elseif((NOT ("${AZURE_SPHERE_HW_DEFINITION}" STREQUAL "")) AND (NOT ("${AZURE_SPHERE_HW_DIRECTORY}" STREQUAL "")))
        list(APPEND AZURE_SPHERE_PACKAGE_COMMAND_ARG "--hardware-definitions;${AZURE_SPHERE_HW_DIRECTORY},${AZURE_SPHERE_SDK_PATH}/HardwareDefinitions/;--target-definition-filename;${AZURE_SPHERE_HW_DEFINITION}")

        target_include_directories(${target} SYSTEM PUBLIC "${AZURE_SPHERE_SDK_PATH}/HardwareDefinitions/inc")
        target_include_directories(${target} SYSTEM PUBLIC "${AZURE_SPHERE_SDK_PATH}/HardwareDefinitions/inc/hw")
    endif()

    # Build list of files on which the image package depends, namely the (unmodified) app manifest,
    # executable, and resource files.
    set(pkg_deps "${ATAIPC_APP_MANIFEST};${AZURE_SPHERE_APPROOT_DIR}/bin/app")
    foreach(res_file ${ATAIPC_RESOURCE_FILES})
        list(APPEND pkg_deps "${AZURE_SPHERE_APPROOT_DIR}/${res_file}")
    endforeach()

    # Get azsphere executable which packages the approot directory into an image package.
    if(${CMAKE_HOST_WIN32})
        set(azsphere_path "${AZURE_SPHERE_SDK_PATH}/Tools_v2/wbin/azsphere.cmd")
    else()
        set(azsphere_path "${AZURE_SPHERE_SDK_PATH}/Links/azsphere_v2")
    endif()

    add_custom_command(OUTPUT "${CMAKE_BINARY_DIR}/${PROJECT_NAME}.imagepackage"
        COMMAND "${azsphere_path}" image-package pack-application "${AZURE_SPHERE_PACKAGE_COMMAND_ARG}"
        DEPENDS ${pkg_deps}
        COMMAND_EXPAND_LISTS)

    # Add MakeImage target
    add_custom_target(MakeImage ALL
        DEPENDS "${CMAKE_BINARY_DIR}/${PROJECT_NAME}.imagepackage")

    add_dependencies(MakeImage ${PROJECT_NAME})
endfunction()
