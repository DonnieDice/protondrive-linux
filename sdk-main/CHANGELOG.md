# Changelog

Every version is tagged using `cs` or `js` prefix following with `/v` and semver, e.g.: `js/v1.2.3`. Details about each version is tracked in this file.

## js/v0.3.1 (2025-09-11)

* Fix listing shared by me
* Fix decryption of bookmarks with custom password
* Fix errors to use correct specific type (any API not found error to be based on ValidationError)

## js/v0.3.0 (2025-09-04)

* Add node details to the diagnostic tool
* Update of `NodeAlreadyExistsValidationError`:
    * Renamed to `NodeWithSameNameExistsValidationError`
    * Renamed `ongoingUploadByOtherClient` to `isUnfinishedUpload`
* Update what key is used to invite users to be ready for admin roles
* Update of node decryption algorithm to improve performance
* Update of loading shared nodes to improve performance
* Fix accessing non-existing node (throwing not found error instead of undefined)
* Fix errors to use correct specific type (decryption error to use DecryptionError or not found error to be based on ValidationError)
* Fix accepting invitation and revision objects in the interface

## js/v0.2.1 (2025-08-20)

* Update of `Bookmark` entity:
    * Added `customPassword` field
    * Updated `url` field to not include custom password
* Fix parsing of modification time of nodes from the cache
* Fix generic validation error from API to be identified as such

## js/v0.2.0 (2025-08-14)

* Add `getSeekableStream` to the `FileDownloader` interface
* Add verification error details to the `Author` error
* Update of `Node` entity:
    * Added `membership` object including `inviteTime` and `sharedBy` fields
    * Renamed `directMemberRole` to `directRole`
* Update of telemetry events:
    * Added `uid` field to `decryptionError` and `verificationError` events to allow client to de-duplicate reports
    * Added `error` field to the `verificationError` event to pass verification details
    * Renamed `logEvent` to `recordMetric` to avoid confusion with logging

## js/v0.1.2 (2025-08-04)

* Fix upload of revisions
* Fix processing of events

## js/v0.1.1 (2025-08-01)

* Add `node.uid` property to the `Invitation` entity
* Update `iterateNodes` to batch requests to API and handle fetches to different volumes in parallel
* Update download algorithm to skip obsolete block signatures
* Fix accept of invitations
* Fix re-export of event types

## js/v0.1.0 (2025-07-29)

* Add `numberOfInitializedDownloads` field to the `PublicLink` entity
* Add `clientUid` property to settings to identify the client
* Add support of loading thumbnails from multiple volumes
* Add diagnostic tool to check the integrity of the user's data
* Update of event system:
    * Added `treeEventScopeId` to `Node` entity
    * Added `subscribeToTreeEvents`
    * Added `subscribeToDriveEvents`
    * Removed `subscribeToRemoteDataUpdates`
    * Removed `subscribeToDevices`
    * Removed `subscribeToFolder`
    * Removed `subscribeToTrashedNodes`
    * Removed `subscribeToSharedNodesByMe`
    * Removed `subscribeToSharedNodesWithMe`
* Fix rename or move of nodes after previous move operation

## js/v0.0.13 (2025-07-18)

* Add `existingNodeUid` parameter to `NodeAlreadyExistsValidationError`
* Add partial support of album nodes
* Update all nodes in the user's volume to have `Admin` role by default
* Update iterating nodes functions to decrypt nodes in parallel
* Update upload algorithm to create draft on the server side when the stream is passed instead of at file uploader initialization
* Fix to not return photos or albums in shared with me nodes
* Fix types of Date fileds in `Revision` entity

## js/v0.0.12 (2025-07-10)

* Fix publish of js package

## js/v0.0.11 (2025-07-09)

* Add support of bookmarks
* Add `deprecatedShareId` field to `Node` entity for web's backward compatibility
* Update of telemetry events:
    * Added `MetricBlockVerificationErrorEvent` event
    * Added `originalError` field including the whole error object for upload and download events
    * Renamed `context` field to `volumeType`
    * Removed `5xx` error type
* Fix updating expiration time of public links
* Fix types of Date fields in `Node` entities
* Fix empty error message in `APIHTTPError` if there is no specific status text
* Remove clear text node names from log messages

## js/v0.0.10 (2025-06-26)

* Add management of public links
* Add `shareId` to `Device` entity for web's backward compatibility
* Fix stuck download for large files

## js/v0.0.9 (2025-06-24)

* Add `getNodeUid` function
* Add `resendInvitation` function
* Update of CryptoProxy interface to follow web monorepo: interfaces for keys
* Update of `nodeDecryptionError` telemetry event: `nodeFolderExtendedAttributes` and `nodeActiveRevision` are now `nodeExtendedAttributes` field

## js/v0.0.8 (2025-06-19)

* Fix external invitation for sharing
* Update of CryptoProxy interface to follow web monorepo: passphrase can be null

## js/v0.0.7 (2025-06-18)

* Fix move operation: reusing passphrase session key

## js/v0.0.6 (2025-06-17)

* Update of CryptoProxy interface to follow web monorepo: array of keys or single key can be passed
* Fix invitation: only main public key should be passed

## js/v0.0.5 (2025-06-11)

* Add `getNode` function

## js/v0.0.4 (2025-06-05)

* Initial version
