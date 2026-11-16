{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module Domain.Content
    ( CreateActivityRequest(..)
    , ActivityDTO(..)
    , ContentDTO(..)
    , validarNovaAtividade
    , rowParaActivityDTO
    , montarContentDTO
    , conteudoIdParaDominio
    , dominioParaConteudoId
    , tituloParaDominio
    , dominioParaSlug
    ) where

import Control.Applicative ((<|>))
import Data.Aeson (FromJSON(..), ToJSON(..), object, withObject, (.:), (.=))
import Data.Text (Text)
import qualified Data.Text as T
import Data.Types (Conteudo(..))
import GHC.Generics (Generic)
import Infrastructure.Database (AtividadeRow(..), ConteudoRow(..))

data CreateActivityRequest = CreateActivityRequest
    { reqActivityConteudoId  :: Int
    , reqActivityTitulo      :: Text
    , reqActivityDescricao   :: Text
    , reqActivityDificuldade :: Int
    } deriving (Show, Eq, Generic)

instance FromJSON CreateActivityRequest where
    parseJSON = withObject "CreateActivityRequest" $ \v ->
        CreateActivityRequest
            <$> (v .: "conteudo_id" <|> v .: "content_id")
            <*> (v .: "titulo" <|> v .: "title")
            <*> (v .: "descricao" <|> v .: "description")
            <*> (v .: "dificuldade" <|> v .: "difficulty")

instance ToJSON CreateActivityRequest where
    toJSON req = object
        [ "conteudo_id" .= reqActivityConteudoId req
        , "titulo"      .= reqActivityTitulo req
        , "descricao"   .= reqActivityDescricao req
        , "dificuldade" .= reqActivityDificuldade req
        ]

data ActivityDTO = ActivityDTO
    { actDtoId          :: Int
    , actDtoConteudoId  :: Int
    , actDtoTitulo      :: Text
    , actDtoDescricao   :: Text
    , actDtoDificuldade :: Int
    } deriving (Show, Eq, Generic)

instance ToJSON ActivityDTO where
    toJSON dto = object
        [ "id"          .= actDtoId dto
        , "conteudo_id" .= actDtoConteudoId dto
        , "titulo"      .= actDtoTitulo dto
        , "descricao"   .= actDtoDescricao dto
        , "dificuldade" .= actDtoDificuldade dto
        ]

instance FromJSON ActivityDTO where
    parseJSON = withObject "ActivityDTO" $ \v ->
        ActivityDTO
            <$> v .: "id"
            <*> v .: "conteudo_id"
            <*> v .: "titulo"
            <*> v .: "descricao"
            <*> v .: "dificuldade"

data ContentDTO = ContentDTO
    { contDtoId            :: Int
    , contDtoTitulo        :: Text
    , contDtoSlug          :: Text
    , contDtoDescricao     :: Text
    , contDtoCategoria     :: Text
    , contDtoNivel         :: Int
    , contDtoPreRequisitos :: [Int]
    , contDtoAtividades    :: [ActivityDTO]
    } deriving (Show, Eq, Generic)

instance ToJSON ContentDTO where
    toJSON dto = object
        [ "id"             .= contDtoId dto
        , "titulo"         .= contDtoTitulo dto
        , "slug"           .= contDtoSlug dto
        , "descricao"      .= contDtoDescricao dto
        , "categoria"      .= contDtoCategoria dto
        , "nivel"          .= contDtoNivel dto
        , "pre_requisitos" .= contDtoPreRequisitos dto
        , "atividades"     .= contDtoAtividades dto
        ]

validarNovaAtividade :: CreateActivityRequest -> Either Text CreateActivityRequest
validarNovaAtividade req
    | T.null (T.strip (reqActivityTitulo req)) =
        Left "O titulo da atividade e obrigatorio."
    | T.null (T.strip (reqActivityDescricao req)) =
        Left "A descricao da atividade e obrigatoria."
    | reqActivityDificuldade req < 1 || reqActivityDificuldade req > 5 =
        Left "A dificuldade da atividade deve estar entre 1 e 5."
    | otherwise =
        Right req
            { reqActivityTitulo    = T.strip (reqActivityTitulo req)
            , reqActivityDescricao = T.strip (reqActivityDescricao req)
            }

rowParaActivityDTO :: AtividadeRow -> ActivityDTO
rowParaActivityDTO row = ActivityDTO
    { actDtoId          = ativId row
    , actDtoConteudoId  = ativConteudoId row
    , actDtoTitulo      = ativTitulo row
    , actDtoDescricao   = ativDescricao row
    , actDtoDificuldade = ativDificuldade row
    }

montarContentDTO :: ConteudoRow -> [Int] -> [AtividadeRow] -> ContentDTO
montarContentDTO row prereqs atividades = ContentDTO
    { contDtoId            = contId row
    , contDtoTitulo        = contTitulo row
    , contDtoSlug          = maybe (T.toLower (contTitulo row)) dominioParaSlug (tituloParaDominio (contTitulo row))
    , contDtoDescricao     = contDescricao row
    , contDtoCategoria     = contCategoria row
    , contDtoNivel         = contNivel row
    , contDtoPreRequisitos = prereqs
    , contDtoAtividades    = map rowParaActivityDTO atividades
    }

conteudoIdParaDominio :: Int -> Maybe Conteudo
conteudoIdParaDominio 1 = Just Adicao
conteudoIdParaDominio 2 = Just Subtracao
conteudoIdParaDominio 3 = Just Multiplicacao
conteudoIdParaDominio 4 = Just Divisao
conteudoIdParaDominio _ = Nothing

dominioParaConteudoId :: Conteudo -> Int
dominioParaConteudoId Adicao        = 1
dominioParaConteudoId Subtracao     = 2
dominioParaConteudoId Multiplicacao = 3
dominioParaConteudoId Divisao       = 4

tituloParaDominio :: Text -> Maybe Conteudo
tituloParaDominio txt =
    case T.toLower (T.strip txt) of
        "adicao"        -> Just Adicao
        "adição"        -> Just Adicao
        "subtracao"     -> Just Subtracao
        "subtração"     -> Just Subtracao
        "multiplicacao" -> Just Multiplicacao
        "multiplicação" -> Just Multiplicacao
        "divisao"       -> Just Divisao
        "divisão"       -> Just Divisao
        _               -> Nothing

dominioParaSlug :: Conteudo -> Text
dominioParaSlug Adicao        = "adicao"
dominioParaSlug Subtracao     = "subtracao"
dominioParaSlug Multiplicacao = "multiplicacao"
dominioParaSlug Divisao       = "divisao"
