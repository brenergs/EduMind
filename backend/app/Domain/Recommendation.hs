{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module Domain.Recommendation
    ( AnswerRequest(..)
    , AnswerResponseDTO(..)
    , ContentPerformanceDTO(..)
    , StudentPerformanceResponse(..)
    , RecommendationItemDTO(..)
    , StudentRecommendationsResponse(..)
    , TrainModelRequestDTO(..)
    , TrainModelResponseDTO(..)
    , ModelStatusDTO(..)
    ) where

import Data.Aeson (FromJSON(..), ToJSON(..), object, withObject, (.!=), (.:), (.:?), (.=))
import Data.Text (Text)
import Data.Time (UTCTime)
import GHC.Generics (Generic)

data AnswerRequest = AnswerRequest
    { ansStudentId      :: Int
    , ansActivityId     :: Int
    , ansCorrect        :: Bool
    , ansAttempts       :: Int
    , ansResolutionTime :: Maybe Int
    , ansAnswerText     :: Maybe Text
    } deriving (Show, Eq, Generic)

instance FromJSON AnswerRequest where
    parseJSON = withObject "AnswerRequest" $ \v ->
        AnswerRequest
            <$> v .: "student_id"
            <*> v .: "activity_id"
            <*> v .: "correct"
            <*> v .:? "attempts" .!= 1
            <*> v .:? "resolution_time"
            <*> v .:? "answer"

instance ToJSON AnswerRequest where
    toJSON req = object
        [ "student_id"      .= ansStudentId req
        , "activity_id"     .= ansActivityId req
        , "correct"         .= ansCorrect req
        , "attempts"        .= ansAttempts req
        , "resolution_time" .= ansResolutionTime req
        , "answer"          .= ansAnswerText req
        ]

data AnswerResponseDTO = AnswerResponseDTO
    { ansRespId             :: Int
    , ansRespStudentId      :: Int
    , ansRespActivityId     :: Int
    , ansRespContentId      :: Int
    , ansRespCorrect        :: Bool
    , ansRespAttempts       :: Int
    , ansRespResolutionTime :: Maybe Int
    , ansRespUpdatedScore   :: Double
    , ansRespRecordedAt     :: UTCTime
    } deriving (Show, Eq, Generic)

instance ToJSON AnswerResponseDTO where
    toJSON dto = object
        [ "answer_id"       .= ansRespId dto
        , "student_id"      .= ansRespStudentId dto
        , "activity_id"     .= ansRespActivityId dto
        , "content_id"      .= ansRespContentId dto
        , "correct"         .= ansRespCorrect dto
        , "attempts"        .= ansRespAttempts dto
        , "resolution_time" .= ansRespResolutionTime dto
        , "updated_score"   .= ansRespUpdatedScore dto
        , "recorded_at"     .= ansRespRecordedAt dto
        ]

data ContentPerformanceDTO = ContentPerformanceDTO
    { perfContentId     :: Int
    , perfContentSlug   :: Text
    , perfContentTitle  :: Text
    , perfScore         :: Double
    , perfAttempts      :: Int
    , perfCorrectCount  :: Int
    , perfAvgTime       :: Maybe Double
    , perfUpdatedAt     :: Maybe UTCTime
    } deriving (Show, Eq, Generic)

instance ToJSON ContentPerformanceDTO where
    toJSON dto = object
        [ "content_id"              .= perfContentId dto
        , "content"                 .= perfContentSlug dto
        , "title"                   .= perfContentTitle dto
        , "score"                   .= perfScore dto
        , "attempts"                .= perfAttempts dto
        , "correct_answers"         .= perfCorrectCount dto
        , "average_resolution_time" .= perfAvgTime dto
        , "updated_at"              .= perfUpdatedAt dto
        ]

data StudentPerformanceResponse = StudentPerformanceResponse
    { studPerfStudentId     :: Int
    , studPerfStudentName   :: Text
    , studPerfOverallScore  :: Double
    , studPerfTotalAttempts :: Int
    , studPerfContents      :: [ContentPerformanceDTO]
    } deriving (Show, Eq, Generic)

instance ToJSON StudentPerformanceResponse where
    toJSON dto = object
        [ "student_id"     .= studPerfStudentId dto
        , "student_name"   .= studPerfStudentName dto
        , "overall_score"  .= studPerfOverallScore dto
        , "total_attempts" .= studPerfTotalAttempts dto
        , "contents"       .= studPerfContents dto
        ]

data RecommendationItemDTO = RecommendationItemDTO
    { recItemContent             :: Text
    , recItemEstimatedMastery    :: Double
    , recItemRecommendation      :: Text
    , recItemReason              :: Text
    , recItemSuggestedDifficulty :: Int
    } deriving (Show, Eq, Generic)

instance ToJSON RecommendationItemDTO where
    toJSON dto = object
        [ "content"              .= recItemContent dto
        , "estimated_mastery"    .= recItemEstimatedMastery dto
        , "recommendation"       .= recItemRecommendation dto
        , "reason"               .= recItemReason dto
        , "suggested_difficulty" .= recItemSuggestedDifficulty dto
        ]

data StudentRecommendationsResponse = StudentRecommendationsResponse
    { recsStudentId       :: Int
    , recsRecommendations :: [RecommendationItemDTO]
    , recsModelVersion    :: Text
    } deriving (Show, Eq, Generic)

instance ToJSON StudentRecommendationsResponse where
    toJSON dto = object
        [ "student_id"      .= recsStudentId dto
        , "recommendations" .= recsRecommendations dto
        , "model_version"   .= recsModelVersion dto
        ]

data TrainModelRequestDTO = TrainModelRequestDTO
    { trainReqVersion      :: Maybe Text
    , trainReqLearningRate :: Maybe Double
    , trainReqEpochs       :: Maybe Int
    , trainReqL2           :: Maybe Double
    } deriving (Show, Eq, Generic)

instance FromJSON TrainModelRequestDTO where
    parseJSON = withObject "TrainModelRequestDTO" $ \v ->
        TrainModelRequestDTO
            <$> v .:? "version"
            <*> v .:? "learning_rate"
            <*> v .:? "epochs"
            <*> v .:? "l2"

data TrainModelResponseDTO = TrainModelResponseDTO
    { trainRespAlgorithm      :: Text
    , trainRespVersion        :: Text
    , trainRespTrainLoss      :: Double
    , trainRespValidationLoss :: Double
    , trainRespTestLoss       :: Double
    , trainRespStatus         :: Text
    } deriving (Show, Eq, Generic)

instance ToJSON TrainModelResponseDTO where
    toJSON dto = object
        [ "algorithm"       .= trainRespAlgorithm dto
        , "model_version"   .= trainRespVersion dto
        , "train_loss"      .= trainRespTrainLoss dto
        , "validation_loss" .= trainRespValidationLoss dto
        , "test_loss"       .= trainRespTestLoss dto
        , "status"          .= trainRespStatus dto
        ]

data ModelStatusDTO = ModelStatusDTO
    { statusModelActive    :: Bool
    , statusModelAlgorithm :: Text
    , statusModelVersion   :: Text
    , statusModelMetrics   :: Text
    , statusModelTrainedAt :: Maybe UTCTime
    } deriving (Show, Eq, Generic)

instance ToJSON ModelStatusDTO where
    toJSON dto = object
        [ "active"        .= statusModelActive dto
        , "algorithm"     .= statusModelAlgorithm dto
        , "model_version" .= statusModelVersion dto
        , "metrics"       .= statusModelMetrics dto
        , "trained_at"    .= statusModelTrainedAt dto
        ]
