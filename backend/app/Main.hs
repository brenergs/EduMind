-- Stub inicial do Passo 4.1; implementação completa prevista no Passo 4.3.
module Main where

import Infrastructure.Database (carregarConfigBanco, inicializarPool, fecharPool)

main :: IO ()
main = do
    cfg <- carregarConfigBanco
    pool <- inicializarPool cfg
    putStrLn ("EduMind backend inicializado (banco: " ++ dbNameConfig cfg ++ ").")
    fecharPool pool
  where
    dbNameConfig = show

