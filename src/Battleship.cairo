 %lang starknet
from starkware.cairo.common.bool import TRUE
from starkware.cairo.common.math_cmp import is_le_felt
from starkware.cairo.common.hash import hash2
from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin
from starkware.cairo.common.uint256 import Uint256, uint256_le, uint256_unsigned_div_rem, uint256_sub
from starkware.starknet.common.syscalls import get_caller_address
from starkware.cairo.common.math import unsigned_div_rem, assert_le_felt, assert_le
from starkware.cairo.common.alloc import alloc
from starkware.starknet.common.syscalls import (
    get_block_number,
    get_block_timestamp,
)


struct Game{
Defender:felt,
Attacker:felt,
Defender_score:felt,
Attacker_score:felt,
RootHash:felt,
EndTime:felt,
attemptCounter: felt,
Winner:felt,

}
 
@storage_var
func Position_shoot(game_id:felt,round:felt,row:felt,col:felt) -> (isPositionHit : felt){
}
@storage_var
func game_counter() -> (game_counter : felt){
}
@storage_var
func games(game_idx : felt) -> (game_struct : Game){
}


// This function can be called by anyone and A new came will be created.
// Player1 will be treated as defender, and they will have to choose 5 positions and place the battle ship.
// Player 2 will be treated as Attacker , and the have to guess any 5 positions where the battle ship is placed.

@external
func set_up_game{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(player1 : felt, player2 : felt)->(n:felt){
    let (gc) = game_counter.read();
    let newGc = gc + 1;
    let firstPlayer = player1;
    let secondPlayer = player2;
    let gameinit = Game(firstPlayer, secondPlayer,5,0,0,0,0,0);
    games.write(gc, gameinit);
    game_counter.write(newGc);
    return (n=newGc);
}

// Defender will have to call this function and pass the merkel root. where leafs contains all details about each positions in grid.
// The Attacker will have to attack the grid within 300 sec once defender set's the battleship
@external
func choose_square{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(game_id : felt, hash : felt){
    let (game) = games.read(game_id);
        let (caller) = get_caller_address();

let (block_timestamp) = get_block_timestamp();
assert caller = game.Defender;
game.Defender = hash;
game.EndTime = block_timestamp + 300;
games.write(game_id, game);
return();
}


// This function needs to called by attacker and he will have to pass leaf detail of the chooses leaf ie. row,col,1
@external
func attack{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(game_id : felt,array_len : felt, array : felt*,proof:felt){
   let (game) = games.read(game_id);
        let (caller) = get_caller_address();

let (block_timestamp) = get_block_timestamp();
assert caller = game.Attacker;
assert_le( game.EndTime,block_timestamp);
assert_le( game.attemptCounter,6);
assert_le(array[0] ,5);
assert_le(array[1] ,5);
assert array[2] = 1;
let isWinner = merkle_verify(array,game.RootHash,25,proof);
game.attemptCounter = game.attemptCounter +1;
if (isWinner == 1){
    game.Defender_score = game.Defender_score -1;
    game.Attacker_score = game.Attacker_score +1;
}
if (game.attemptCounter == 5){
    game.Winner = game.Attacker_score;
    
    if(game.Defender_score == 3 ){
    game.Winner = game.Defender_score;
    }
    if(game.Defender_score == 4 ){
    game.Winner = game.Defender_score;
    }
    if(game.Defender_score == 5 ){
    game.Winner = game.Defender_score;
    }
    
}
games.write(game_id, game);
return();
}

func merkle_verify{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    leaf : felt, root : felt, proof_len : felt, proof : felt*
) -> (res : felt){
alloc_locals;
    let (calc_root) = _merkle_verify_body(leaf, proof_len, proof);
   if (calc_root == root) {
        return (res=1);
    } else {
        return (res=0);
    }

}

func _hash_sorted{hash_ptr : HashBuiltin*, range_check_ptr}(a, b) -> (res:felt){
  let le = is_le_felt(a, b);

    if( le == 1){
        let (n) = hash2{hash_ptr=hash_ptr}(a, b);
        }else{
        let (n) = hash2{hash_ptr=hash_ptr}(b, a);
        }    
    return (res=n);
}

func _merkle_verify_body{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    curr : felt, proof_len : felt, proof : felt*
) -> (res : felt){
    alloc_locals;

    if (proof_len == 0){
        return (res=curr);
    }

    let (n) = _hash_sorted{hash_ptr=pedersen_ptr}(curr, [proof]);

    let (res) = _merkle_verify_body(n, proof_len - 1, proof + 1);
    return (res=res);
}

func merkle_build{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    leafs_len : felt, leafs : felt*
) -> (res : felt){
    alloc_locals;
    if (leafs_len == 1){
        return (res=[leafs]);
    }
    let (local new_leafs) = alloc();
    _merkle_build_body{new_leafs=new_leafs, leafs=leafs, stop=leafs_len}(0);

    let (q, r) = unsigned_div_rem(leafs_len, 2);
    return merkle_build(q + r, new_leafs);
}

func _merkle_build_body{
    syscall_ptr : felt*,
    pedersen_ptr : HashBuiltin*,
    range_check_ptr,
    new_leafs : felt*,
    leafs : felt*,
    stop : felt,
}(i : felt){
    let stop_loop = is_le_felt(stop, i);
    if (stop_loop == TRUE){
        return ();
    }
    if( i == stop - 1){
        let (n) = _hash_sorted{hash_ptr=pedersen_ptr}([leafs + i], [leafs + i]);
        tempvar range_check_ptr = range_check_ptr;
        } else{
        let (n) = _hash_sorted{hash_ptr=pedersen_ptr}([leafs + i], [leafs + i + 1]);
        tempvar range_check_ptr = range_check_ptr;
        }
    
    assert [new_leafs + i / 2] = n;
    return _merkle_build_body(i + 2);
}

func addresses_to_leafs{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    allow_list_len : felt, allow_list : felt*
) -> (leafs_len : felt, leafs : felt*){
    alloc_locals;
    let (local leafs) = alloc();
    _addresses_to_leafs_body{leafs=leafs, allow_list=allow_list, stop=allow_list_len}(0);
    return (allow_list_len, leafs);
}

func _addresses_to_leafs_body{
    syscall_ptr : felt*,
    pedersen_ptr : HashBuiltin*,
    range_check_ptr,
    leafs : felt*,
    allow_list : felt*,
    stop : felt,
}(i : felt){
    if(i == stop){
        return ();
    }
    let (n) = hash2{hash_ptr=pedersen_ptr}([allow_list + i], [allow_list + i]);
    assert [leafs + i] = n;
    return _addresses_to_leafs_body(i + 1);
}
