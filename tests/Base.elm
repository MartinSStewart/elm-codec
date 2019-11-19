module Base exposing (roundtrips, suite)

import Bytes exposing (Bytes)
import Bytes.Encode
import Codec.Bytes as Codec exposing (Codec)
import Dict
import Expect exposing (Expectation)
import Fuzz exposing (Fuzzer)
import Set
import Test exposing (Test, describe, fuzz, test)


suite : Test
suite =
    describe "Testing roundtrips"
        [ describe "Basic" basicTests
        , describe "Containers" containersTests
        , describe "Object" objectTests
        , describe "Custom" customTests
        , describe "bimap" bimapTests
        , describe "andThen" andThenTests
        , describe "errorTests" errorTests
        , describe "lazy" lazyTests
        , describe "maybe" maybeTests
        , describe "constant"
            [ test "roundtrips"
                (\_ ->
                    Codec.constant 632
                        |> (\d -> Codec.decode d (Bytes.Encode.sequence [] |> Bytes.Encode.encode))
                        |> Expect.equal (Ok 632)
                )
            ]
        ]


roundtrips : Fuzzer a -> Codec a -> Test
roundtrips fuzzer codec =
    fuzz fuzzer "is a roundtrip" <|
        \value ->
            value
                |> Codec.encode codec
                |> Codec.decode codec
                |> Expect.equal (Ok value)


roundtripsWithin : Fuzzer Float -> Codec Float -> Test
roundtripsWithin fuzzer codec =
    fuzz fuzzer "is a roundtrip" <|
        \value ->
            value
                |> Codec.encode codec
                |> Codec.decode codec
                |> Result.withDefault -999.1234567
                |> Expect.within (Expect.Relative 0.000001) value


basicTests : List Test
basicTests =
    [ describe "Codec.string"
        [ roundtrips Fuzz.string Codec.string
        ]
    , describe "Codec.signedInt"
        [ roundtrips signedInt32Fuzz Codec.signedInt32
        ]
    , describe "Codec.unsignedInt"
        [ roundtrips unsignedInt32Fuzz Codec.unsignedInt32
        ]
    , describe "Codec.float64"
        [ roundtrips Fuzz.float Codec.float64
        ]
    , describe "Codec.float32"
        [ roundtripsWithin Fuzz.float Codec.float32
        ]
    , describe "Codec.bool"
        [ roundtrips Fuzz.bool Codec.bool
        ]
    , describe "Codec.char"
        [ roundtrips Fuzz.char Codec.char
        ]
    , describe "Codec.bytes"
        [ roundtrips fuzzBytes Codec.bytes
        ]
    ]


fuzzBytes : Fuzzer Bytes
fuzzBytes =
    Fuzz.list unsignedInt32Fuzz |> Fuzz.map (List.map (Bytes.Encode.unsignedInt32 Bytes.LE) >> Bytes.Encode.sequence >> Bytes.Encode.encode)


containersTests : List Test
containersTests =
    [ describe "Codec.array"
        [ roundtrips (Fuzz.array signedInt32Fuzz) (Codec.array Codec.signedInt32)
        ]
    , describe "Codec.list"
        [ roundtrips (Fuzz.list signedInt32Fuzz) (Codec.list Codec.signedInt32)
        ]
    , describe "Codec.dict"
        [ roundtrips
            (Fuzz.map2 Tuple.pair Fuzz.string signedInt32Fuzz
                |> Fuzz.list
                |> Fuzz.map Dict.fromList
            )
            (Codec.dict Codec.string Codec.signedInt32)
        ]
    , describe "Codec.set"
        [ roundtrips
            (Fuzz.list signedInt32Fuzz |> Fuzz.map Set.fromList)
            (Codec.set Codec.signedInt32)
        ]
    , describe "Codec.tuple"
        [ roundtrips
            (Fuzz.tuple ( signedInt32Fuzz, signedInt32Fuzz ))
            (Codec.tuple Codec.signedInt32 Codec.signedInt32)
        ]
    ]


unsignedInt32Fuzz =
    Fuzz.intRange 0 4294967295


signedInt32Fuzz =
    Fuzz.intRange -2147483648 2147483647


objectTests : List Test
objectTests =
    [ describe "with 0 fields"
        [ roundtrips (Fuzz.constant {})
            (Codec.record {}
                |> Codec.finishRecord
            )
        ]
    , describe "with 1 field"
        [ roundtrips (Fuzz.map (\i -> { fname = i }) signedInt32Fuzz)
            (Codec.record (\i -> { fname = i })
                |> Codec.field .fname Codec.signedInt32
                |> Codec.finishRecord
            )
        ]
    , describe "with 2 fields"
        [ roundtrips
            (Fuzz.map2
                (\a b ->
                    { a = a
                    , b = b
                    }
                )
                signedInt32Fuzz
                signedInt32Fuzz
            )
            (Codec.record
                (\a b ->
                    { a = a
                    , b = b
                    }
                )
                |> Codec.field .a Codec.signedInt32
                |> Codec.field .b Codec.signedInt32
                |> Codec.finishRecord
            )
        ]
    ]


type Newtype a
    = Newtype a


type Newtype6 a b c d e f
    = Newtype6 a b c d e f


customTests : List Test
customTests =
    [ describe "with 1 ctor, 0 args"
        [ roundtrips (Fuzz.constant ())
            (Codec.customType
                (\f v ->
                    case v of
                        () ->
                            f
                )
                |> Codec.variant0 ()
                |> Codec.finishCustomType
            )
        ]
    , describe "with 1 ctor, 1 arg"
        [ roundtrips (Fuzz.map Newtype signedInt32Fuzz)
            (Codec.customType
                (\f v ->
                    case v of
                        Newtype a ->
                            f a
                )
                |> Codec.variant1 Newtype Codec.signedInt32
                |> Codec.finishCustomType
            )
        ]
    , describe "with 1 ctor, 6 arg"
        [ roundtrips (Fuzz.map5 (Newtype6 0) signedInt32Fuzz signedInt32Fuzz signedInt32Fuzz signedInt32Fuzz signedInt32Fuzz)
            (Codec.customType
                (\function v ->
                    case v of
                        Newtype6 a b c d e f ->
                            function a b c d e f
                )
                |> Codec.variant6 Newtype6 Codec.signedInt32 Codec.signedInt32 Codec.signedInt32 Codec.signedInt32 Codec.signedInt32 Codec.signedInt32
                |> Codec.finishCustomType
            )
        ]
    , describe "with 2 ctors, 0,1 args" <|
        let
            match fnothing fjust value =
                case value of
                    Nothing ->
                        fnothing

                    Just v ->
                        fjust v

            codec =
                Codec.customType match
                    |> Codec.variant0 Nothing
                    |> Codec.variant1 Just Codec.signedInt32
                    |> Codec.finishCustomType

            fuzzers =
                [ ( "1st ctor", Fuzz.constant Nothing )
                , ( "2nd ctor", Fuzz.map Just signedInt32Fuzz )
                ]
        in
        fuzzers
            |> List.map
                (\( name, fuzz ) ->
                    describe name
                        [ roundtrips fuzz codec ]
                )
    ]


bimapTests : List Test
bimapTests =
    [ roundtrips Fuzz.float <|
        Codec.map
            (\x -> x * 2)
            (\x -> x / 2)
            Codec.float64
    ]


{-| Volume must be between 0 and 1.
-}
volumeCodec =
    Codec.float64
        |> Codec.andThen
            (\volume ->
                if volume <= 1 && volume >= 0 then
                    Ok volume

                else
                    Err "Volume is outside of valid range."
            )
            (\volume -> volume)


andThenTests : List Test
andThenTests =
    [ roundtrips (Fuzz.floatRange 0 1) <| volumeCodec
    , test "andThen fails on invalid binary data." <|
        \_ ->
            5
                |> Codec.encode volumeCodec
                |> Codec.decode volumeCodec
                |> Expect.equal (Codec.BaseError "Volume is outside of valid range." |> Err)
    ]


type alias Record =
    { a : Int
    , b : Float
    , c : String
    , d : String
    }


errorTests : List Test
errorTests =
    [ test "variant produces correct error message." <|
        \_ ->
            let
                codec =
                    Codec.customType
                        (\encodeNothing encodeJust value ->
                            case value of
                                Nothing ->
                                    encodeNothing

                                Just v ->
                                    encodeJust v
                        )
                        |> Codec.variant0 Nothing
                        |> Codec.variant1 Just Codec.signedInt32
                        |> Codec.finishCustomType

                codecBad =
                    Codec.customType
                        (\encodeNothing _ encodeJust value ->
                            case value of
                                Nothing ->
                                    encodeNothing

                                Just v ->
                                    encodeJust v
                        )
                        |> Codec.variant0 Nothing
                        |> Codec.variant0 Nothing
                        |> Codec.variant1 Just Codec.signedInt32
                        |> Codec.finishCustomType
            in
            Codec.encode codecBad (Just 0) |> Codec.decode codec |> Expect.equal (Err Codec.NoVariantMatches)
    , test "list produces correct error message." <|
        \_ ->
            let
                codec =
                    Codec.list volumeCodec
            in
            Codec.encode codec [ 0, 3, 0, 4, 0, 0 ]
                |> Codec.decode codec
                |> Expect.equal
                    (Codec.ListError
                        { listIndex = 1
                        , error = Codec.BaseError "Volume is outside of valid range."
                        }
                        |> Err
                    )
    , test "Record produces correct error message." <|
        \_ ->
            let
                codec =
                    Codec.record Record
                        |> Codec.field .a Codec.unsignedInt32
                        |> Codec.field .b volumeCodec
                        |> Codec.field .c Codec.string
                        |> Codec.field .d Codec.string
                        |> Codec.finishRecord
            in
            Codec.encode codec { a = 0, b = -1, c = "", d = "" }
                |> Codec.decode codec
                |> Expect.equal
                    (Codec.RecordError
                        { fieldIndex = 1
                        , error = Codec.BaseError "Volume is outside of valid range."
                        }
                        |> Err
                    )
    ]


type Peano
    = Peano (Maybe Peano)


{-| This is the same example used in Codec.recursive but adapted for lazy.
-}
peanoCodec : Codec Peano
peanoCodec =
    Codec.maybe (Codec.lazy (\() -> peanoCodec)) |> Codec.map Peano (\(Peano a) -> a)


lazyTests : List Test
lazyTests =
    [ roundtrips peanoFuzz peanoCodec
    ]


peanoFuzz : Fuzzer Peano
peanoFuzz =
    Fuzz.intRange 0 10 |> Fuzz.map (intToPeano Nothing)


intToPeano : Maybe Peano -> Int -> Peano
intToPeano peano value =
    if value <= 0 then
        Peano Nothing

    else
        intToPeano peano (value - 1) |> Just |> Peano


maybeTests : List Test
maybeTests =
    [ describe "single"
        [ roundtrips
            (Fuzz.oneOf
                [ Fuzz.constant Nothing
                , Fuzz.map Just signedInt32Fuzz
                ]
            )
          <|
            Codec.maybe Codec.signedInt32
        ]
    ]
