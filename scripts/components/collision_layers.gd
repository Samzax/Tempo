## Constantes de camada de colisao 2D. Fonte unica do ADR-008.
## Numeros de camada (bit 0 = camada 1): world=1, player=2, enemy=4,
## player_bullet=8, enemy_bullet=16, pickup=32.
class_name CollisionLayers extends RefCounted

## Camada 1 - geometria estatica do mundo.
const WORLD := 1
## Camada 2 - corpos dos jogadores.
const PLAYER := 2
## Camada 3 - inimigos.
const ENEMY := 4
## Camada 4 - projeteis do jogador.
const PLAYER_BULLET := 8
## Camada 5 - projeteis inimigos.
const ENEMY_BULLET := 16
## Camada 6 - pickups/deployables recolhaveis.
const PICKUP := 32
