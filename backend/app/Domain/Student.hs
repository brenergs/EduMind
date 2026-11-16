{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module Domain.Student
    ( CreateStudentRequest(..)
    , StudentDTO(..)
    , validarNovoEstudante
    , rowParaStudentDTO
    ) where

import Control.Applicative ((<|>))
import Data.Aeson (FromJSON(..), ToJSON(..), object, withObject, (.:), (.=))
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (UTCTime)
import GHC.Generics (Generic)
import Infrastructure.Database (EstudanteRow(..))

data CreateStudentRequest = CreateStudentRequest
    { reqStudentNome  :: Text
    , reqStudentEmail :: Text
    } deriving (Show, Eq, Generic)

instance FromJSON CreateStudentRequest where
    parseJSON = withObject "CreateStudentRequest" $ \v ->
        CreateStudentRequest
            <$> (v .: "nome" <|> v .: "name")
            <*> v .: "email"

instance ToJSON CreateStudentRequest where
    toJSON req = object
        [ "nome"  .= reqStudentNome req
        , "email" .= reqStudentEmail req
        ]

data StudentDTO = StudentDTO
    { studentDtoId           :: Int
    , studentDtoNome         :: Text
    , studentDtoEmail        :: Text
    , studentDtoDataCadastro :: UTCTime
    } deriving (Show, Eq, Generic)

instance ToJSON StudentDTO where
    toJSON dto = object
        [ "id"            .= studentDtoId dto
        , "nome"          .= studentDtoNome dto
        , "email"         .= studentDtoEmail dto
        , "data_cadastro" .= studentDtoDataCadastro dto
        ]

instance FromJSON StudentDTO where
    parseJSON = withObject "StudentDTO" $ \v ->
        StudentDTO
            <$> v .: "id"
            <*> (v .: "nome" <|> v .: "name")
            <*> v .: "email"
            <*> v .: "data_cadastro"

validarNovoEstudante :: CreateStudentRequest -> Either Text (Text, Text)
validarNovoEstudante req =
    let nomeLimpo  = T.strip (reqStudentNome req)
        emailLimpo = T.toLower (T.strip (reqStudentEmail req))
    in if T.null nomeLimpo
        then Left "O nome do estudante e obrigatorio."
        else if not (emailValido emailLimpo)
            then Left "E-mail do estudante invalido."
            else Right (nomeLimpo, emailLimpo)

emailValido :: Text -> Bool
emailValido email =
    let (usuario, dominioComArroba) = T.breakOn "@" email
        dominio = T.drop 1 dominioComArroba
    in not (T.null usuario)
        && not (T.null dominio)
        && T.isInfixOf "." dominio
        && not (T.any (== ' ') email)

rowParaStudentDTO :: EstudanteRow -> StudentDTO
rowParaStudentDTO row = StudentDTO
    { studentDtoId           = estId row
    , studentDtoNome         = estNome row
    , studentDtoEmail        = estEmail row
    , studentDtoDataCadastro = estDataCadastro row
    }
