//
//  ShelfView.swift
//  notch
//
//  The notch "tray": a single expanded drop zone for query context. Dropping
//  images here stages them in `NotchTextInputController` — the same ephemeral,
//  never-persisted store the composer uses — so they ride the next query to the
//  worker and clear after it sends. Non-image drops are ignored.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ShelfView: View {
    @EnvironmentObject var vm: ViewModel
    @ObservedObject private var controller = NotchTextInputController.shared
    private let spacing: CGFloat = 8

    var body: some View {
        panel
            .onDrop(of: [.image, .fileURL], isTargeted: $vm.dragDetectorTargeting) { providers in
                handleDrop(providers: providers)
            }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        // Stage the images as ephemeral context, then hand the user straight to the
        // text box with those image(s) attached: close the tray and open the
        // composer (attachments populate reactively as each provider finishes
        // loading). `dropEvent` stops the drop-zone debounce from racing our close.
        vm.dropEvent = true
        controller.ingest(providers: providers)
        controller.showComposerAfterTrayCloses()
        withAnimation(vm.animation) {
            vm.close()
        }
        return true
    }

    private var panel: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(
                vm.dragDetectorTargeting
                    ? Color.accentColor.opacity(0.9)
                    : Color.white.opacity(0.1),
                style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [10])
            )
            .overlay {
                content
                    .padding()
            }
            .transaction { transaction in
                transaction.animation = vm.animation
            }
            .contentShape(Rectangle())
    }

    private var content: some View {
        Group {
            if controller.attachments.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray.and.arrow.down")
                        .symbolVariant(.fill)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white, .gray)
                        .imageScale(.large)

                    Text("Drop images here")
                        .foregroundStyle(.gray)
                        .font(.system(.title3, design: .rounded))
                        .fontWeight(.medium)
                }
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: spacing) {
                        ForEach(controller.attachments) { attachment in
                            thumbnail(attachment)
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
    }

    private func thumbnail(_ attachment: NotchTextInputAttachment) -> some View {
        Image(nsImage: attachment.thumbnail)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Button {
                    controller.removeAttachment(id: attachment.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.white, .black.opacity(0.55))
                }
                .buttonStyle(.plain)
                .offset(x: 5, y: -5)
            }
            .help(attachment.fileName)
    }
}
