module Main (main) where

import qualified Cardano.Api                    as Api
import qualified Data.ByteString                as BS
import qualified Data.ByteString.Lazy           as LBS
import           System.Directory               (doesFileExist)
import           System.FilePath                ((</>))
import           Test.Tasty                     (defaultMain, testGroup)
import           Test.Tasty.Golden              (goldenVsString)
import           Test.Tasty.HUnit               (assertEqual, testCase, (@=?))

import           GeniusYield.Examples.Gift
import           GeniusYield.GYConfig           (coreConfigIO,
                                                 findMaestroTokenAndNetId)
import           GeniusYield.Imports
import           GeniusYield.Test.CoinSelection (coinSelectionTests)
import           GeniusYield.Test.Config        (configTests)
import           GeniusYield.Test.GYTxBody      (gyTxBodyTests)
import           GeniusYield.Test.GYTxSkeleton  (gyTxSkeletonTests)
import           GeniusYield.Test.Providers     (providersTests)
import           GeniusYield.Test.RefInput      (refInputTests)
import           GeniusYield.Test.SlotConfig    (slotConversionTests)
import           GeniusYield.Types

-------------------------------------------------------------------------------
-- main
-------------------------------------------------------------------------------

main :: IO ()
main = do
    configs <- forM ["maestro-config.json", "blockfrost-config.json"] coreConfigIO
    (providerToken, netId) <- findMaestroTokenAndNetId configs
    rootDir <- findPackageRoot
    defaultMain $ testGroup "atlas"
        [ testGroup "serializeToRawBytes"
            [ goldenVsString "serialized-v1" (rootDir </> "fixtures" </> "script-v1.cbor") $ do
                return $ LBS.fromStrict $ Api.serialiseToRawBytes simpleScriptAPIv1
            , goldenVsString "serialized-v2" (rootDir </> "fixtures" </> "script-v2.cbor") $ do
                return $ LBS.fromStrict $ Api.serialiseToRawBytes simpleScriptAPIv2

            , testCase "Encoding is the same" $ do
                v1 <- BS.readFile $ rootDir </> "fixtures" </> "script-v1.cbor"
                v2 <- BS.readFile $ rootDir </> "fixtures" </> "script-v2.cbor"
                assertEqual "v1==v2" v1 v2
            ]

        , testGroup "textEnvelope"
            [ goldenVsString "serialized-v1"  (rootDir </> "fixtures" </> "script-env-v1.json") $ do
                return $ Api.textEnvelopeToJSON Nothing simpleScriptAPIv1
            , goldenVsString "serialized-v2"  (rootDir </> "fixtures" </> "script-env-v2.json") $ do
                return $ Api.textEnvelopeToJSON Nothing simpleScriptAPIv2

            -- we can deserialize v1 as v1.
            , testCase "deserialize v1" $ do
                e <- Api.readFileTextEnvelope (Api.proxyToAsType Proxy) (Api.File $ rootDir </> "fixtures" </> "script-env-v1.json")
                Right simpleScriptAPIv1 @=? first show e

            , testCase "deserialize v1" $ do
                e <- Api.readFileTextEnvelope (Api.proxyToAsType Proxy) (Api.File $ rootDir </> "fixtures" </> "script-env-v1.json")

                let expected :: Either String (Api.PlutusScript Api.PlutusScriptV2)
                    expected = Left "(TextEnvelopeTypeError [TextEnvelopeType \"PlutusScriptV2\"] (TextEnvelopeType \"PlutusScriptV1\"))"

                expected  @=? first (dropWhile (/= '(') . show) e
            ]
        , slotConversionTests
        , coinSelectionTests
        , gyTxBodyTests
        , configTests
        , gyTxSkeletonTests
        , refInputTests
        , providersTests configs providerToken netId
        ]

-------------------------------------------------------------------------------
-- simple script
-------------------------------------------------------------------------------

simpleScriptAPIv1 :: Api.PlutusScript Api.PlutusScriptV1
simpleScriptAPIv1 = validatorToApi giftValidatorV1

simpleScriptAPIv2 :: Api.PlutusScript Api.PlutusScriptV2
simpleScriptAPIv2 = validatorToApi giftValidatorV2

-------------------------------------------------------------------------------
-- utilities
-------------------------------------------------------------------------------

-- | Useful when tests are run with @cabal run@ from the root of the project,
-- not the package.
findPackageRoot :: IO FilePath
findPackageRoot = do
    here <- doesFileExist "atlas-cardano.cabal"
    if here
    then return "."
    else fail "Cannot find package root"
