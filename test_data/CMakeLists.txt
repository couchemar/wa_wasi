cmake_minimum_required(VERSION 3.20)
project(WaWasiTestData NONE)

# Find all WAT fixture sources. CONFIGURE_DEPENDS re-globs on build so new or
# renamed .wat files are picked up without re-running cmake by hand.
file(GLOB WAT_SOURCES CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/wat/*.wat")

# WAT -> WASM (wat2wasm with all proposals enabled, matching the sibling
# wa_embedder fixture chain).
foreach(WAT_FILE ${WAT_SOURCES})
    get_filename_component(BASENAME ${WAT_FILE} NAME_WE)
    add_custom_command(
        OUTPUT ${CMAKE_CURRENT_SOURCE_DIR}/wat/${BASENAME}.wasm
        COMMAND wat2wasm --enable-all ${WAT_FILE}
                -o ${CMAKE_CURRENT_SOURCE_DIR}/wat/${BASENAME}.wasm
        DEPENDS ${WAT_FILE}
        COMMENT "Compiling ${BASENAME}.wat"
    )
    list(APPEND WAT_WASM_FILES ${CMAKE_CURRENT_SOURCE_DIR}/wat/${BASENAME}.wasm)
endforeach()

# Default target. When there are no .wat fixtures yet the target is empty and
# builds successfully (the pure accessor-level unit tests need no fixtures).
add_custom_target(wat_wasm ALL DEPENDS ${WAT_WASM_FILES})
