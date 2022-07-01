//
// Copyright © 2020 osy. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import SwiftUI

@available(iOS 14, macOS 11, *)
struct VMConfigQEMUView: View {
    private struct Argument: Identifiable {
        let id: Int
        let string: String
    }
    
    @Binding var config: UTMQemuConfigurationQEMU
    @Binding var system: UTMQemuConfigurationSystem
    let fetchFixedArguments: () -> [QEMUArgument]
    @State private var showExportLog: Bool = false
    @State private var showExportArgs: Bool = false
    @EnvironmentObject private var data: UTMData
    
    private var logExists: Bool {
        guard let path = config.dataURL else {
            return false
        }
        let logPath = path.appendingPathComponent(QEMUPackageFileName.debugLog.rawValue)
        return FileManager.default.fileExists(atPath: logPath.path)
    }
    
    private var supportsUefi: Bool {
        [.arm, .aarch64, .i386, .x86_64].contains(system.architecture)
    }
    
    private var supportsPs2: Bool {
        if system.target.rawValue.starts(with: "pc") || system.target.rawValue.starts(with: "q35") {
            return true
        } else {
            return false
        }
    }
    
    private var supportsHypervisor: Bool {
        #if arch(arm64)
        return system.architecture == .aarch64
        #elseif arch(x86_64)
        return system.architecture == .x86_64
        #else
        return false
        #endif
    }
    
    var body: some View {
        VStack {
            Form {
                Section(header: Text("Logging")) {
                    Toggle(isOn: $config.hasDebugLog, label: {
                        Text("Debug Logging")
                    })
                    Button("Export Debug Log") {
                        showExportLog.toggle()
                    }.modifier(VMShareItemModifier(isPresented: $showExportLog, shareItem: exportDebugLog()))
                    .disabled(!logExists)
                }
                DetailedSection("Tweaks", description: "These are advanced settings affecting QEMU which should be kept default unless you are running into issues.") {
                    Toggle("UEFI Boot", isOn: $config.hasUefiBoot)
                        .disabled(!supportsUefi)
                        .help("Should be off for older operating systems such as Windows 7 or lower.")
                    Toggle("RNG Device", isOn: $config.hasRNGDevice)
                        .help("Should be on always unless the guest cannot boot because of this.")
                    Toggle("Balloon Device", isOn: $config.hasBalloonDevice)
                        .help("Should be on always unless the guest cannot boot because of this.")
                    Toggle("TPM Device", isOn: $config.hasTPMDevice)
                        .help("This is required to boot Windows 11.")
                    #if os(macOS)
                    Toggle("Use Hypervisor", isOn: $config.hasHypervisor)
                        .disabled(!supportsHypervisor)
                        .help("Only available if host architecture matches the target. Otherwise, TCG emulation is used.")
                    #endif
                    Toggle("Use local time for base clock", isOn: $config.hasRTCLocalTime)
                        .help("If checked, use local time for RTC which is required for Windows. Otherwise, use UTC clock.")
                    Toggle("Force PS/2 controller", isOn: $config.hasPS2Controller)
                        .disabled(!supportsPs2)
                        .help("Instantiate PS/2 controller even when USB input is supported. Required for older Windows.")
                }
                DetailedSection("QEMU Machine Properties", description: "This is appended to the -machine argument.") {
                    DefaultTextField("", text: $config.machinePropertyOverride.bound, prompt: "Default")
                }
                Section(header: Text("QEMU Arguments")) {
                    let fixedArgs = fetchFixedArguments()
                    Button("Export QEMU Command") {
                        showExportArgs.toggle()
                    }.modifier(VMShareItemModifier(isPresented: $showExportArgs, shareItem: exportArgs(fixedArgs)))
                    #if os(macOS)
                    VStack {
                        ForEach(fixedArgs) { arg in
                            TextField("", text: .constant(arg.string))
                        }.disabled(true)
                        CustomArguments(config: $config)
                        NewArgumentTextField(config: $config)
                    }
                    #else
                    List {
                        ForEach(fixedArgs) { arg in
                            Text(arg.string)
                        }.foregroundColor(.secondary)
                        CustomArguments(config: $config)
                        NewArgumentTextField(config: $config)
                    }
                    #endif
                }
            }.navigationBarItems(trailing: EditButton())
            .disableAutocorrection(true)
        }
    }
    
    private func exportDebugLog() -> VMShareItemModifier.ShareItem? {
        guard let path = config.dataURL else {
            return nil
        }
        let srcLogPath = path.appendingPathComponent(UTMLegacyQemuConfiguration.debugLogName)
        return .debugLog(srcLogPath)
    }
    
    private func exportArgs(_ args: [QEMUArgument]) -> VMShareItemModifier.ShareItem {
        var argString = "qemu-system-\(system.architecture.rawValue)"
        for arg in args {
            if arg.string.contains(" ") {
                argString += " \"\(arg.string)\""
            } else {
                argString += " \(arg.string)"
            }
        }
        for arg in config.additionalArguments {
            argString += " \(arg.string)"
        }
        return .qemuCommand(argString)
    }
}

@available(iOS 14, macOS 11, *)
struct CustomArguments: View {
    @Binding var config: UTMQemuConfigurationQEMU
    
    var body: some View {
        ForEach($config.additionalArguments) { $arg in
            let i = config.additionalArguments.firstIndex(of: arg) ?? 0
            HStack {
                DefaultTextField("", text: $arg.string, prompt: "(Delete)", onEditingChanged: { editing in
                    if !editing && arg.string == "" {
                        config.additionalArguments.remove(at: i)
                    }
                })
                #if os(macOS)
                Spacer()
                if i != 0 {
                    Button(action: {
                        config.additionalArguments.move(fromOffsets: IndexSet(integer: i), toOffset: i-1)
                    }, label: {
                        Label("Move Up", systemImage: "arrow.up").labelStyle(.iconOnly)
                    })
                }
                #endif
            }
        }.onDelete { offsets in
            config.additionalArguments.remove(atOffsets: offsets)
        }
        .onMove { offsets, index in
            config.additionalArguments.move(fromOffsets: offsets, toOffset: index)
        }
    }
}

@available(iOS 14, macOS 11, *)
struct NewArgumentTextField: View {
    @Binding var config: UTMQemuConfigurationQEMU
    @State private var newArg: String = ""
    
    var body: some View {
        Group {
            DefaultTextField("", text: $newArg, prompt: "New...", onEditingChanged: addArg)
        }.onDisappear {
            if newArg != "" {
                addArg(editing: false)
            }
        }
    }
    
    private func addArg(editing: Bool) {
        guard !editing else {
            return
        }
        if newArg != "" {
            config.additionalArguments.append(QEMUArgument(newArg))
        }
        newArg = ""
    }
}

@available(iOS 14, macOS 11, *)
struct VMConfigQEMUView_Previews: PreviewProvider {
    @State static private var config = UTMQemuConfigurationQEMU()
    @State static private var system = UTMQemuConfigurationSystem()
    
    static var previews: some View {
        VMConfigQEMUView(config: $config, system: $system, fetchFixedArguments: { [] })
    }
}
