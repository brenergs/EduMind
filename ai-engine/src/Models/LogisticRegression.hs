{-# LANGUAGE DeriveGeneric #-}

module Models.LogisticRegression
    ( ModeloLogistico(..)
    , sigmoid
    , prever
    , perda
    , perdaMedia
    ) where

import Data.Aeson (FromJSON, ToJSON)
import GHC.Generics (Generic)

data ModeloLogistico = ModeloLogistico
    { pesos :: [Double]
    , bias  :: Double
    } deriving (Show, Eq, Generic)

instance ToJSON ModeloLogistico
instance FromJSON ModeloLogistico

sigmoid :: Double -> Double
sigmoid z
    | z >= 0    = 1.0 / (1.0 + exp (-z))
    | otherwise = let ez = exp z in ez / (1.0 + ez) -- numericamente estável para z muito negativo

prever :: [Double] -> [Double] -> Double -> Double
prever ws entradas b =
    sigmoid (sum (zipWith (*) ws entradas) + b)

perda :: Double -> Double -> Double
perda y previsto =
    negate
        ( y * log (max 1e-15 previsto)
        + (1.0 - y) * log (max 1e-15 (1.0 - previsto))
        )

perdaMedia :: [(Double, Double)] -> Double
perdaMedia [] = 0.0
perdaMedia pares =
    sum [perda y p | (y, p) <- pares] / fromIntegral (length pares)

