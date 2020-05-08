{-# LANGUAGE DuplicateRecordFields      #-}
{-# LANGUAGE OverloadedStrings          #-}
{-# LANGUAGE TemplateHaskell            #-}
{-# LANGUAGE DataKinds                  #-}
{-# LANGUAGE GADTs                      #-}
{-# LANGUAGE TypeFamilies               #-}
{-# LANGUAGE TypeInType                 #-}
{-# LANGUAGE TypeApplications           #-}
{-# LANGUAGE KindSignatures             #-}
{-# LANGUAGE FlexibleInstances          #-}
{-# LANGUAGE FlexibleContexts           #-}
{-# LANGUAGE StandaloneDeriving         #-}
{-# LANGUAGE ExistentialQuantification  #-}
{-# LANGUAGE MultiParamTypeClasses      #-}
{-# LANGUAGE FunctionalDependencies     #-}
{-# LANGUAGE ScopedTypeVariables        #-}
{-# OPTIONS_GHC -Wno-unticked-promoted-constructors #-}
module Language.Haskell.LSP.Types.Message where

import qualified Data.Aeson                                 as A
import           Data.Aeson.TH
import           Data.Aeson.Types
import           Data.Hashable
-- For <= 8.2.2
import           Data.Text                                  (Text)
import           Language.Haskell.LSP.Types.Constants
import           Language.Haskell.LSP.Types.Utils
import           Data.Function (on)
import Data.Kind
import Control.Applicative
import qualified Data.Map as M
import Data.Some
import Unsafe.Coerce


-- | Id used for a request, Can be either a String or an Int
data LspId (m :: Method p Request) = IdInt Int | IdString Text
  deriving (Show,Read,Eq,Ord)

instance A.ToJSON (LspId m) where
  toJSON (IdInt i)    = toJSON i
  toJSON (IdString s) = toJSON s

instance A.FromJSON (LspId m) where
  parseJSON v@(A.Number _) = IdInt <$> parseJSON v
  parseJSON  (A.String  s) = return (IdString s)
  parseJSON _              = mempty

instance Hashable (LspId m) where
  hashWithSalt salt (IdInt i) = hashWithSalt salt i
  hashWithSalt salt (IdString s) = hashWithSalt salt s

type LspIdRsp m = Maybe (LspId m)

-- a `compare` b <=> toBase a `compare` toBase b
-- toBase (i :: f a) == toBase (j :: f b) <=> a ~ b
class Ord (Base f) => IxOrd f where
  type Base f
  toBase :: forall a. f a -> Base f

instance IxOrd LspId where
  type Base LspId = Either Int Text
  toBase (IdInt i) = Left i
  toBase (IdString s) = Right s

newtype IxMap (k :: a -> Type) (f :: a -> Type) = IxMap { getMap :: M.Map (Base k) (Some f) }
type IdMap (f :: Method FromServer Request -> Type) = IxMap (LspId :: Method FromServer Request -> Type)  f

emptyIxMap :: IxMap k f
emptyIxMap = IxMap M.empty

insertIxMap :: IxOrd k => k m -> f m -> IxMap k f -> IxMap k f
insertIxMap i x (IxMap m) = IxMap $ M.insert (toBase i) (mkSome x) m

lookupIxMap :: IxOrd k => k m -> IxMap k f -> Maybe (f m)
lookupIxMap i (IxMap m) =
  case M.lookup (toBase i) m of
    Just (Some v) -> Just $ unsafeCoerce v
    Nothing -> Nothing

pickFromIxMap :: IxOrd k => k m -> IxMap k f -> (Maybe (f m), IxMap k f)
pickFromIxMap i = pickFromIxMap' (toBase i)

pickFromIxMap' :: IxOrd k => Base k -> IxMap k f -> (Maybe (f m), IxMap k f)
pickFromIxMap' i (IxMap m) =
  case M.updateLookupWithKey (\_ _ -> Nothing) i m of
    (Nothing,m) -> (Nothing,IxMap m)
    (Just (Some k),m) -> (Just (unsafeCoerce k),IxMap m)

requestId :: LspIdRsp m -> LspId m
requestId (Just x) = x
requestId Nothing  = error "reponse with no id"

responseId :: LspId m -> LspIdRsp m
responseId = Just
-- ---------------------------------------------------------------------

data Provenance = FromServer   | FromClient
data MethodType = Notification | Request

data Method (p :: Provenance) (t :: MethodType) where
-- Client Methods
  -- General
  Initialize                         :: Method FromClient Request
  Initialized                        :: Method FromClient Notification
  Shutdown                           :: Method FromClient Request
  Exit                               :: Method FromClient Notification
  -- Workspace
  WorkspaceDidChangeWorkspaceFolders :: Method FromClient Notification
  WorkspaceDidChangeConfiguration    :: Method FromClient Notification
  WorkspaceDidChangeWatchedFiles     :: Method FromClient Notification
  WorkspaceSymbol                    :: Method FromClient Request
  WorkspaceExecuteCommand            :: Method FromClient Request
  -- Progress
  WorkDoneProgressCancel             :: Method FromClient Notification
  -- Document
  TextDocumentDidOpen                :: Method FromClient Notification
  TextDocumentDidChange              :: Method FromClient Notification
  TextDocumentWillSave               :: Method FromClient Notification
  TextDocumentWillSaveWaitUntil      :: Method FromClient Request
  TextDocumentDidSave                :: Method FromClient Notification
  TextDocumentDidClose               :: Method FromClient Notification
  -- Completion
  TextDocumentCompletion             :: Method FromClient Request
  CompletionItemResolve              :: Method FromClient Request
  -- LanguageQueries
  TextDocumentHover                  :: Method FromClient Request
  TextDocumentSignatureHelp          :: Method FromClient Request
  TextDocumentDefinition             :: Method FromClient Request
  TextDocumentTypeDefinition         :: Method FromClient Request
  TextDocumentImplementation         :: Method FromClient Request
  TextDocumentReferences             :: Method FromClient Request
  TextDocumentDocumentHighlight      :: Method FromClient Request
  TextDocumentDocumentSymbol         :: Method FromClient Request
  -- Code Action/Lens/Link
  TextDocumentCodeAction             :: Method FromClient Request
  TextDocumentCodeLens               :: Method FromClient Request
  CodeLensResolve                    :: Method FromClient Request
  TextDocumentDocumentLink           :: Method FromClient Request
  DocumentLinkResolve                :: Method FromClient Request
  -- Syntax highlighting/Coloring
  TextDocumentDocumentColor          :: Method FromClient Request
  TextDocumentColorPresentation      :: Method FromClient Request
  -- Formatting
  TextDocumentFormatting             :: Method FromClient Request
  TextDocumentRangeFormatting        :: Method FromClient Request
  TextDocumentOnTypeFormatting       :: Method FromClient Request
  -- Rename
  TextDocumentRename                 :: Method FromClient Request
  TextDocumentPrepareRename          :: Method FromClient Request
  -- FoldingRange
  TextDocumentFoldingRange           :: Method FromClient Request

-- ServerMethods
  -- Window
  WindowShowMessage                  :: Method FromServer Notification
  WindowShowMessageRequest           :: Method FromServer Request
  WindowLogMessage                   :: Method FromServer Notification
  WindowWorkDoneProgressCreate       :: Method FromServer Request
  Progress                           :: Method FromServer Notification
  TelemetryEvent                     :: Method FromServer Notification
  -- Capability
  ClientRegisterCapability           :: Method FromServer Request
  ClientUnregisterCapability         :: Method FromServer Request
  -- Workspace
  WorkspaceWorkspaceFolders          :: Method FromServer Request
  WorkspaceConfiguration             :: Method FromServer Request
  WorkspaceApplyEdit                 :: Method FromServer Request
  -- Document
  TextDocumentPublishDiagnostics     :: Method FromServer Notification

-- Cancelling
  CancelRequest                      :: Method p Notification

-- Custom
  -- A custom message type. It is not enforced that this starts with $/.
  CustomMethod                       :: Method p t

data SMethod (m :: Method p t) where
  SInitialize                         :: SMethod Initialize
  SInitialized                        :: SMethod Initialized
  SShutdown                           :: SMethod Shutdown
  SExit                               :: SMethod Exit
  SWorkspaceDidChangeWorkspaceFolders :: SMethod WorkspaceDidChangeWorkspaceFolders
  SWorkspaceDidChangeConfiguration    :: SMethod WorkspaceDidChangeConfiguration
  SWorkspaceDidChangeWatchedFiles     :: SMethod WorkspaceDidChangeWatchedFiles
  SWorkspaceSymbol                    :: SMethod WorkspaceSymbol
  SWorkspaceExecuteCommand            :: SMethod WorkspaceExecuteCommand
  SWorkDoneProgressCancel             :: SMethod WorkDoneProgressCancel
  STextDocumentDidOpen                :: SMethod TextDocumentDidOpen
  STextDocumentDidChange              :: SMethod TextDocumentDidChange
  STextDocumentWillSave               :: SMethod TextDocumentWillSave
  STextDocumentWillSaveWaitUntil      :: SMethod TextDocumentWillSaveWaitUntil
  STextDocumentDidSave                :: SMethod TextDocumentDidSave
  STextDocumentDidClose               :: SMethod TextDocumentDidClose
  STextDocumentCompletion             :: SMethod TextDocumentCompletion
  SCompletionItemResolve              :: SMethod CompletionItemResolve
  STextDocumentHover                  :: SMethod TextDocumentHover
  STextDocumentSignatureHelp          :: SMethod TextDocumentSignatureHelp
  STextDocumentDefinition             :: SMethod TextDocumentDefinition
  STextDocumentTypeDefinition         :: SMethod TextDocumentTypeDefinition
  STextDocumentImplementation         :: SMethod TextDocumentImplementation
  STextDocumentReferences             :: SMethod TextDocumentReferences
  STextDocumentDocumentHighlight      :: SMethod TextDocumentDocumentHighlight
  STextDocumentDocumentSymbol         :: SMethod TextDocumentDocumentSymbol
  STextDocumentCodeAction             :: SMethod TextDocumentCodeAction
  STextDocumentCodeLens               :: SMethod TextDocumentCodeLens
  SCodeLensResolve                    :: SMethod CodeLensResolve
  STextDocumentDocumentLink           :: SMethod TextDocumentDocumentLink
  SDocumentLinkResolve                :: SMethod DocumentLinkResolve
  STextDocumentDocumentColor          :: SMethod TextDocumentDocumentColor
  STextDocumentColorPresentation      :: SMethod TextDocumentColorPresentation
  STextDocumentFormatting             :: SMethod TextDocumentFormatting
  STextDocumentRangeFormatting        :: SMethod TextDocumentRangeFormatting
  STextDocumentOnTypeFormatting       :: SMethod TextDocumentOnTypeFormatting
  STextDocumentRename                 :: SMethod TextDocumentRename
  STextDocumentPrepareRename          :: SMethod TextDocumentPrepareRename
  STextDocumentFoldingRange           :: SMethod TextDocumentFoldingRange

  SWindowShowMessage                  :: SMethod WindowShowMessage
  SWindowShowMessageRequest           :: SMethod WindowShowMessageRequest
  SWindowLogMessage                   :: SMethod WindowLogMessage
  SWindowWorkDoneProgressCreate       :: SMethod WindowWorkDoneProgressCreate
  SProgress                           :: SMethod Progress
  STelemetryEvent                     :: SMethod TelemetryEvent
  SClientRegisterCapability           :: SMethod ClientRegisterCapability
  SClientUnregisterCapability         :: SMethod ClientUnregisterCapability
  SWorkspaceWorkspaceFolders          :: SMethod WorkspaceWorkspaceFolders
  SWorkspaceConfiguration             :: SMethod WorkspaceConfiguration
  SWorkspaceApplyEdit                 :: SMethod WorkspaceApplyEdit
  STextDocumentPublishDiagnostics     :: SMethod TextDocumentPublishDiagnostics

  SCancelRequest                      :: SMethod CancelRequest
  SCustomMethod                       :: Text -> SMethod CustomMethod

deriving instance Eq   (SMethod m)
deriving instance Ord  (SMethod m)
deriving instance Show (SMethod m)

data SomeClientMethod = forall t (m :: Method FromClient t). SomeClientMethod (SMethod m)
data SomeServerMethod = forall t (m :: Method FromServer t). SomeServerMethod (SMethod m)

data SomeMethod where
  SomeMethod :: forall m. SMethod m -> SomeMethod

deriving instance Show SomeMethod
instance Eq SomeMethod where
  (==) = (==) `on` toJSON
instance Ord SomeMethod where
  compare = compare `on` (getString . toJSON)
    where
      getString (A.String t) = t
      getString _ = error "ToJSON instance for some method isn't string"
deriving instance Show SomeClientMethod
instance Eq SomeClientMethod where
  (==) = (==) `on` toJSON
instance Ord SomeClientMethod where
  compare = compare `on` (getString . toJSON)
    where
      getString (A.String t) = t
      getString _ = error "ToJSON instance for some method isn't string"
deriving instance Show SomeServerMethod
instance Eq SomeServerMethod where
  (==) = (==) `on` toJSON
instance Ord SomeServerMethod where
  compare = compare `on` (getString . toJSON)
    where
      getString (A.String t) = t
      getString _ = error "ToJSON instance for some method isn't string"

instance ToJSON SomeMethod where
  toJSON (SomeMethod m) = toJSON m
instance FromJSON SomeMethod where
  parseJSON v = client <|> server
    where
      client = do
        c <- parseJSON v
        case c of
          -- Don't parse the client custom method so that we can still
          -- parse the server methods
          SomeClientMethod (SCustomMethod _) -> mempty
          SomeClientMethod m -> pure $ SomeMethod m
      server = do
        c <- parseJSON v
        case c of
          SomeServerMethod m -> pure $ SomeMethod m


instance ToJSON SomeClientMethod where
  toJSON (SomeClientMethod m) = toJSON m
instance FromJSON SomeClientMethod where
  -- General
  parseJSON (A.String "initialize")                          = pure $ SomeClientMethod SInitialize
  parseJSON (A.String "initialized")                         = pure $ SomeClientMethod SInitialized
  parseJSON (A.String "shutdown")                            = pure $ SomeClientMethod SShutdown
  parseJSON (A.String "exit")                                = pure $ SomeClientMethod SExit
 -- Workspace
  parseJSON (A.String "workspace/didChangeWorkspaceFolders") = pure $ SomeClientMethod SWorkspaceDidChangeWorkspaceFolders
  parseJSON (A.String "workspace/didChangeConfiguration")    = pure $ SomeClientMethod SWorkspaceDidChangeConfiguration
  parseJSON (A.String "workspace/didChangeWatchedFiles")     = pure $ SomeClientMethod SWorkspaceDidChangeWatchedFiles
  parseJSON (A.String "workspace/symbol")                    = pure $ SomeClientMethod SWorkspaceSymbol
  parseJSON (A.String "workspace/executeCommand")            = pure $ SomeClientMethod SWorkspaceExecuteCommand
 -- Document
  parseJSON (A.String "textDocument/didOpen")                = pure $ SomeClientMethod STextDocumentDidOpen
  parseJSON (A.String "textDocument/didChange")              = pure $ SomeClientMethod STextDocumentDidChange
  parseJSON (A.String "textDocument/willSave")               = pure $ SomeClientMethod STextDocumentWillSave
  parseJSON (A.String "textDocument/willSaveWaitUntil")      = pure $ SomeClientMethod STextDocumentWillSaveWaitUntil
  parseJSON (A.String "textDocument/didSave")                = pure $ SomeClientMethod STextDocumentDidSave
  parseJSON (A.String "textDocument/didClose")               = pure $ SomeClientMethod STextDocumentDidClose
  parseJSON (A.String "textDocument/completion")             = pure $ SomeClientMethod STextDocumentCompletion
  parseJSON (A.String "completionItem/resolve")              = pure $ SomeClientMethod SCompletionItemResolve
  parseJSON (A.String "textDocument/hover")                  = pure $ SomeClientMethod STextDocumentHover
  parseJSON (A.String "textDocument/signatureHelp")          = pure $ SomeClientMethod STextDocumentSignatureHelp
  parseJSON (A.String "textDocument/definition")             = pure $ SomeClientMethod STextDocumentDefinition
  parseJSON (A.String "textDocument/typeDefinition")         = pure $ SomeClientMethod STextDocumentTypeDefinition
  parseJSON (A.String "textDocument/implementation")         = pure $ SomeClientMethod STextDocumentImplementation
  parseJSON (A.String "textDocument/references")             = pure $ SomeClientMethod STextDocumentReferences
  parseJSON (A.String "textDocument/documentHighlight")      = pure $ SomeClientMethod STextDocumentDocumentHighlight
  parseJSON (A.String "textDocument/documentSymbol")         = pure $ SomeClientMethod STextDocumentDocumentSymbol
  parseJSON (A.String "textDocument/codeAction")             = pure $ SomeClientMethod STextDocumentCodeAction
  parseJSON (A.String "textDocument/codeLens")               = pure $ SomeClientMethod STextDocumentCodeLens
  parseJSON (A.String "codeLens/resolve")                    = pure $ SomeClientMethod SCodeLensResolve
  parseJSON (A.String "textDocument/documentLink")           = pure $ SomeClientMethod STextDocumentDocumentLink
  parseJSON (A.String "documentLink/resolve")                = pure $ SomeClientMethod SDocumentLinkResolve
  parseJSON (A.String "textDocument/documentColor")          = pure $ SomeClientMethod STextDocumentDocumentColor
  parseJSON (A.String "textDocument/colorPresentation")      = pure $ SomeClientMethod STextDocumentColorPresentation
  parseJSON (A.String "textDocument/formatting")             = pure $ SomeClientMethod STextDocumentFormatting
  parseJSON (A.String "textDocument/rangeFormatting")        = pure $ SomeClientMethod STextDocumentRangeFormatting
  parseJSON (A.String "textDocument/onTypeFormatting")       = pure $ SomeClientMethod STextDocumentOnTypeFormatting
  parseJSON (A.String "textDocument/rename")                 = pure $ SomeClientMethod STextDocumentRename
  parseJSON (A.String "textDocument/prepareRename")          = pure $ SomeClientMethod STextDocumentPrepareRename
  parseJSON (A.String "textDocument/foldingRange")           = pure $ SomeClientMethod STextDocumentFoldingRange
  parseJSON (A.String "window/workDoneProgress/cancel")      = pure $ SomeClientMethod SWorkDoneProgressCancel
-- Cancelling
  parseJSON (A.String "$/cancelRequest")                     = pure $ SomeClientMethod SCancelRequest
-- Custom
  parseJSON (A.String m)                                     = pure $ SomeClientMethod (SCustomMethod m)
  parseJSON _                                                = mempty

instance ToJSON SomeServerMethod where
  toJSON (SomeServerMethod m) = toJSON m
instance A.FromJSON SomeServerMethod where
-- Server
  -- Window
  parseJSON (A.String "window/showMessage")                  = pure $ SomeServerMethod SWindowShowMessage
  parseJSON (A.String "window/showMessageRequest")           = pure $ SomeServerMethod SWindowShowMessageRequest
  parseJSON (A.String "window/logMessage")                   = pure $ SomeServerMethod SWindowLogMessage
  parseJSON (A.String "window/workDoneProgress/create")      = pure $ SomeServerMethod SWindowWorkDoneProgressCreate
  parseJSON (A.String "$/progress")                          = pure $ SomeServerMethod SProgress
  parseJSON (A.String "telemetry/event")                     = pure $ SomeServerMethod STelemetryEvent
  -- Client
  parseJSON (A.String "client/registerCapability")           = pure $ SomeServerMethod SClientRegisterCapability
  parseJSON (A.String "client/unregisterCapability")         = pure $ SomeServerMethod SClientUnregisterCapability
  -- Workspace
  parseJSON (A.String "workspace/workspaceFolders")          = pure $ SomeServerMethod SWorkspaceWorkspaceFolders
  parseJSON (A.String "workspace/configuration")             = pure $ SomeServerMethod SWorkspaceConfiguration
  parseJSON (A.String "workspace/applyEdit")                 = pure $ SomeServerMethod SWorkspaceApplyEdit
  -- Document
  parseJSON (A.String "textDocument/publishDiagnostics")     = pure $ SomeServerMethod STextDocumentPublishDiagnostics

-- Cancelling
  parseJSON (A.String "$/cancelRequest")                     = pure $ SomeServerMethod SCancelRequest

-- Custom
  parseJSON (A.String m)                                     = pure $ SomeServerMethod (SCustomMethod m)
  parseJSON _                                                = mempty

-- ---------------------------------------------------------------------
-- From JSON
-- ---------------------------------------------------------------------

makeSingletonFromJSON 'SomeMethod ''SMethod

-- ---------------------------------------------------------------------
-- TO JSON
-- ---------------------------------------------------------------------

instance A.ToJSON (SMethod m) where
-- Client
  -- General
  toJSON SInitialize                         = A.String "initialize"
  toJSON SInitialized                        = A.String "initialized"
  toJSON SShutdown                           = A.String "shutdown"
  toJSON SExit                               = A.String "exit"
  -- Workspace
  toJSON SWorkspaceDidChangeWorkspaceFolders = A.String "workspace/didChangeWorkspaceFolders"
  toJSON SWorkspaceDidChangeConfiguration    = A.String "workspace/didChangeConfiguration"
  toJSON SWorkspaceDidChangeWatchedFiles     = A.String "workspace/didChangeWatchedFiles"
  toJSON SWorkspaceSymbol                    = A.String "workspace/symbol"
  toJSON SWorkspaceExecuteCommand            = A.String "workspace/executeCommand"
  -- Document
  toJSON STextDocumentDidOpen                = A.String "textDocument/didOpen"
  toJSON STextDocumentDidChange              = A.String "textDocument/didChange"
  toJSON STextDocumentWillSave               = A.String "textDocument/willSave"
  toJSON STextDocumentWillSaveWaitUntil      = A.String "textDocument/willSaveWaitUntil"
  toJSON STextDocumentDidSave                = A.String "textDocument/didSave"
  toJSON STextDocumentDidClose               = A.String "textDocument/didClose"
  toJSON STextDocumentCompletion             = A.String "textDocument/completion"
  toJSON SCompletionItemResolve              = A.String "completionItem/resolve"
  toJSON STextDocumentHover                  = A.String "textDocument/hover"
  toJSON STextDocumentSignatureHelp          = A.String "textDocument/signatureHelp"
  toJSON STextDocumentReferences             = A.String "textDocument/references"
  toJSON STextDocumentDocumentHighlight      = A.String "textDocument/documentHighlight"
  toJSON STextDocumentDocumentSymbol         = A.String "textDocument/documentSymbol"
  toJSON STextDocumentDefinition             = A.String "textDocument/definition"
  toJSON STextDocumentTypeDefinition         = A.String "textDocument/typeDefinition"
  toJSON STextDocumentImplementation         = A.String "textDocument/implementation"
  toJSON STextDocumentCodeAction             = A.String "textDocument/codeAction"
  toJSON STextDocumentCodeLens               = A.String "textDocument/codeLens"
  toJSON SCodeLensResolve                    = A.String "codeLens/resolve"
  toJSON STextDocumentDocumentColor          = A.String "textDocument/documentColor"
  toJSON STextDocumentColorPresentation      = A.String "textDocument/colorPresentation"
  toJSON STextDocumentFormatting             = A.String "textDocument/formatting"
  toJSON STextDocumentRangeFormatting        = A.String "textDocument/rangeFormatting"
  toJSON STextDocumentOnTypeFormatting       = A.String "textDocument/onTypeFormatting"
  toJSON STextDocumentRename                 = A.String "textDocument/rename"
  toJSON STextDocumentPrepareRename          = A.String "textDocument/prepareRename"
  toJSON STextDocumentFoldingRange           = A.String "textDocument/foldingRange"
  toJSON STextDocumentDocumentLink           = A.String "textDocument/documentLink"
  toJSON SDocumentLinkResolve                = A.String "documentLink/resolve"
  toJSON SWorkDoneProgressCancel             = A.String "window/workDoneProgress/cancel"
-- Server
  -- Window
  toJSON SWindowShowMessage                  = A.String "window/showMessage"
  toJSON SWindowShowMessageRequest           = A.String "window/showMessageRequest"
  toJSON SWindowLogMessage                   = A.String "window/logMessage"
  toJSON SWindowWorkDoneProgressCreate       = A.String "window/workDoneProgress/create"
  toJSON SProgress                           = A.String "$/progress"
  toJSON STelemetryEvent                     = A.String "telemetry/event"
  -- Client
  toJSON SClientRegisterCapability           = A.String "client/registerCapability"
  toJSON SClientUnregisterCapability         = A.String "client/unregisterCapability"
  -- Workspace
  toJSON SWorkspaceWorkspaceFolders          = A.String "workspace/workspaceFolders"
  toJSON SWorkspaceConfiguration             = A.String "workspace/configuration"
  toJSON SWorkspaceApplyEdit                 = A.String "workspace/applyEdit"
  -- Document
  toJSON STextDocumentPublishDiagnostics     = A.String "textDocument/publishDiagnostics"
  -- Cancelling
  toJSON SCancelRequest                      = A.String "$/cancelRequest"
-- Custom
  toJSON (SCustomMethod m)                   = A.String m

-- ---------------------------------------------------------------------
{-
interface ResponseError<D> {
    /**
     * A number indicating the error type that occurred.
     */
    code: number;

    /**
     * A string providing a short description of the error.
     */
    message: string;

    /**
     * A Primitive or Structured value that contains additional
     * information about the error. Can be omitted.
     */
    data?: D;
}

export namespace ErrorCodes {
        // Defined by JSON RPC
        export const ParseError: number = -32700;
        export const InvalidRequest: number = -32600;
        export const MethodNotFound: number = -32601;
        export const InvalidParams: number = -32602;
        export const InternalError: number = -32603;
        export const serverErrorStart: number = -32099;
        export const serverErrorEnd: number = -32000;
        export const ServerNotInitialized: number = -32002;
        export const UnknownErrorCode: number = -32001;

        // Defined by the protocol.
        export const RequestCancelled: number = -32800;
        export const ContentModified: number = -32801;
}
-}

data ErrorCode = ParseError
               | InvalidRequest
               | MethodNotFound
               | InvalidParams
               | InternalError
               | ServerErrorStart
               | ServerErrorEnd
               | ServerNotInitialized
               | UnknownErrorCode
               | RequestCancelled
               | ContentModified
               -- ^ Note: server error codes are reserved from -32099 to -32000
               deriving (Read,Show,Eq)

instance A.ToJSON ErrorCode where
  toJSON ParseError           = A.Number (-32700)
  toJSON InvalidRequest       = A.Number (-32600)
  toJSON MethodNotFound       = A.Number (-32601)
  toJSON InvalidParams        = A.Number (-32602)
  toJSON InternalError        = A.Number (-32603)
  toJSON ServerErrorStart     = A.Number (-32099)
  toJSON ServerErrorEnd       = A.Number (-32000)
  toJSON ServerNotInitialized = A.Number (-32002)
  toJSON UnknownErrorCode     = A.Number (-32001)
  toJSON RequestCancelled     = A.Number (-32800)
  toJSON ContentModified      = A.Number (-32801)

instance A.FromJSON ErrorCode where
  parseJSON (A.Number (-32700)) = pure ParseError
  parseJSON (A.Number (-32600)) = pure InvalidRequest
  parseJSON (A.Number (-32601)) = pure MethodNotFound
  parseJSON (A.Number (-32602)) = pure InvalidParams
  parseJSON (A.Number (-32603)) = pure InternalError
  parseJSON (A.Number (-32099)) = pure ServerErrorStart
  parseJSON (A.Number (-32000)) = pure ServerErrorEnd
  parseJSON (A.Number (-32002)) = pure ServerNotInitialized
  parseJSON (A.Number (-32001)) = pure UnknownErrorCode
  parseJSON (A.Number (-32800)) = pure RequestCancelled
  parseJSON (A.Number (-32801)) = pure ContentModified
  parseJSON _                   = mempty

-- -------------------------------------

{-
  https://microsoft.github.io/language-server-protocol/specification#responseMessage

  interface ResponseError {
    /**
    * A number indicating the error type that occurred.
    */
    code: number;

    /**
    * A string providing a short description of the error.
    */
    message: string;

    /**
    * A primitive or structured value that contains additional
    * information about the error. Can be omitted.
    */
    data?: string | number | boolean | array | object | null;
  }
-}

data ResponseError =
  ResponseError
    { _code    :: ErrorCode
    , _message :: Text
    , _xdata   :: Maybe A.Value
    } deriving (Read,Show,Eq)

deriveJSON lspOptions{ fieldLabelModifier = customModifier } ''ResponseError

