#!/usr/bin/env python3
from pathlib import Path
import re,sys
paths={Path(p).name:Path(p).read_text() for p in sys.argv[2:]}
def item(file,signature):
 s=paths[file];a=s.index(signature);b=s.index('{',a);depth=1;end=b+1
 while depth:
  if s[end]=='{':depth+=1
  elif s[end]=='}':depth-=1
  end+=1
 return s[a:end]+'\n'
parts=['import Foundation\nimport UIKit\nimport TelegramCore\nimport TelegramApi\nimport Postbox\nimport SwiftSignalKit\nimport MtProtoKit\nimport SGSimpleSettings\nimport TelegramPresentationData\n']
# Compile production policy/persistence and worker functions. Only the transport and
# account-state manager are replaced with recording fixtures in Probe.swift.
for f in ['WyGramGhostMode.swift','ManagedAccountPresence.swift','ManagedLocalInputActivities.swift']:
 parts.append(paths[f])
for sig in ['enum PeerReadStateValidationError {', 'private func inputPeer(postbox:', 'private func inputSecretChat(postbox:', 'private func pushPeerReadState(network: Network, postbox: Postbox, stateManager: AccountStateManager, peerId: PeerId, readState:', 'private func pushPeerReadState(network: Network, postbox: Postbox, stateManager: AccountStateManager, peerId: PeerId) ->', 'func synchronizePeerReadState(', 'private func synchronizePeerReadStateAllowed(']:
 parts.append(item('SynchronizePeerReadState.swift',sig))
parts.append(item('Stories.swift','func _internal_markStoryAsSeen(').replace('account: Account,','account: ProbeAccount,'))
parts.append(item('Stories.swift','extension Stories.PeerState {'))
parts.append(item('SynchronizeViewStoriesOperation.swift','func _internal_addSynchronizeViewStoriesOperation('))
parts.append(item('ManagedSynchronizeConsumeMessageContentsOperations.swift','private func synchronizeConsumeMessageContents('))
parts.append(paths['ManagedSynchronizeViewStoriesOperations.swift'].replace('withTakenOperation','withTakenStoryOperation'))
for sig in ['func apiInputPeer(_ peer: Peer)', 'func apiInputUser(_ peer: Peer)', 'func apiInputChannel(_ peer: Peer)', 'func apiInputSecretChat(_ peer: Peer)']:
 parts.append(item('ApiUtils.swift',sig))
parts.append(item('WyGramSettingsLayout.swift','class WyGramSettingsTableController:'))
parts.append(item('WyGramGhostModeController.swift','final class WyGramGhostModeController:'))
body='\n'.join(parts)
body=re.sub(r'\bNetwork\b','ProbeNetwork',body)
body=re.sub(r'\bAccountStateManager\b','ProbeStateManager',body)
body=body.replace('private func synchronizeConsumeMessageContents(', 'func synchronizeConsumeMessageContents(')
body=body.replace('private func requestActivity(', 'func requestActivity(')
for name in ['WyGramGhostModeSettings', 'wygramGhostModeSettings', 'wygramUpdateGhostModeSettings']:
 body=body.replace(name,'Fixture'+name)
Path(sys.argv[1]).write_text(body)

