// LLVM 18 pass plugin - Empty registration to avoid ABI incompatibility
//
// ISSUE: The base image's clang was built with different C++ ABI settings
// than what llvm-config --cxxflags returns. This causes crashes when
// registering any callbacks that use std::function.
//
// WORKAROUND: Empty registration allows the plugin to load without crashing.
// The actual bitcode writing functionality is disabled until the ABI
// mismatch is resolved (requires rebuilding clang or the plugin with
// matching flags).

#include "llvm/IR/PassManager.h"
#include "llvm/Passes/PassBuilder.h"
#include "llvm/Passes/PassPlugin.h"

using namespace llvm;

static void registerPasses(PassBuilder& PB) {
    // Empty - cannot register callbacks due to ABI incompatibility
    // between plugin and clang's std::function implementation
}

llvm::PassPluginLibraryInfo getWriteBitcodePluginInfo() {
    return {
        LLVM_PLUGIN_API_VERSION,
        "WriteBitcode",
        "v1.0-noop",
        registerPasses
    };
}

extern "C" LLVM_ATTRIBUTE_WEAK ::llvm::PassPluginLibraryInfo llvmGetPassPluginInfo() {
    return getWriteBitcodePluginInfo();
}
