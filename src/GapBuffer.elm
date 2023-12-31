module GapBuffer exposing
    ( GapBuffer
    , empty, fromArray, fromList
    , get, isEmpty, length, slice, currentFocus
    , getFocus, setFocus, insertAtFocus, updateFocus, focusAt, delete
    , advanceFocus
    , RippleOutcome(..), ripple
    , foldlSlice, foldrSlice, indexedFoldl, indexedFoldr
    )

{-| Implements an efficient buffer for text editing.


# Make a Buffer

@docs GapBuffer
@docs empty, fromArray, fromList


# Query

@docs get, isEmpty, length, slice, currentFocus


# Manipulate

@docs getFocus, setFocus, insertAtFocus, updateFocus, focusAt, delete
@docs advanceFocus


# Rippling

@docs RippleOutcome, ripple


# Iterate

@docs foldlSlice, foldrSlice, indexedFoldl, indexedFoldr

-}

import Array exposing (Array)


{-| A GapBuffer model.
-}
type alias GapBuffer a b =
    { head : Array a
    , zip :
        Maybe
            { val : b
            , at : Int
            , tail : Array a
            }
    , length : Int
    , toFocus : a -> b
    , fromFocus : Maybe a -> b -> a
    }


rezip : Int -> GapBuffer a b -> GapBuffer a b
rezip idx buffer =
    { buffer
        | head = slice 0 idx buffer
        , zip =
            get idx buffer
                |> Maybe.map
                    (\val ->
                        { val = buffer.toFocus val
                        , at = idx
                        , tail = slice (idx + 1) buffer.length buffer
                        }
                    )
    }



-- Make a GapBuffer


{-| Creates an empty `GapBuffer`.
-}
empty : (a -> b) -> (Maybe a -> b -> a) -> GapBuffer a b
empty toFocus fromFocus =
    { head = Array.empty
    , zip = Nothing
    , length = 0
    , toFocus = toFocus
    , fromFocus = fromFocus
    }


{-| Creates a `GapBuffer` from a `List`.
-}
fromList : (a -> b) -> (Maybe a -> b -> a) -> List a -> GapBuffer a b
fromList toFocus fromFocus list =
    let
        array =
            Array.fromList list
    in
    { head = array
    , zip = Nothing
    , length = Array.length array
    , toFocus = toFocus
    , fromFocus = fromFocus
    }


{-| Creates a `GapBuffer` from an `Array`.
-}
fromArray : (a -> b) -> (Maybe a -> b -> a) -> Array a -> GapBuffer a b
fromArray toFocus fromFocus array =
    { head = array
    , zip = Nothing
    , length = Array.length array
    , toFocus = toFocus
    , fromFocus = fromFocus
    }



-- Query


{-| Checks if a `GapBuffer` is empty.
-}
isEmpty : GapBuffer a b -> Bool
isEmpty buffer =
    buffer.length == 0


{-| Gets the number of element in the `GapBuffer`.
-}
length : GapBuffer a b -> Int
length buffer =
    buffer.length


{-| Extracts the element at the specified index in the `GapBuffer`.
If the `GapBuffer` does not hold data for this index, `Nothing` is returned.
-}
get : Int -> GapBuffer a b -> Maybe a
get idx buffer =
    case buffer.zip of
        Nothing ->
            Array.get idx buffer.head

        Just zip ->
            if idx < Array.length buffer.head then
                Array.get idx buffer.head

            else if idx == zip.at then
                buffer.fromFocus (Array.get (zip.at - 1) buffer.head) zip.val |> Just

            else
                Array.get (idx - zip.at - 1) zip.tail


{-| Extracts a slice of data from the buffer, between the _from_ and _to_ indices
specified.

If these indicies go outside the range of the `GapBuffer`, data from the
actual available range will be returned.

If you are iterating over the contents of the buffer, to render a
UI for example, there is no need to copy the contents into an intermediate
`Array`. You can iterate directly over a region of the buffer using the
`foldlSlice` function instead.

-}
slice : Int -> Int -> GapBuffer a b -> Array a
slice from to buffer =
    let
        intersects s1 e1 s2 e2 =
            s1 < e2 && e1 >= s2
    in
    case buffer.zip of
        Nothing ->
            Array.slice from to buffer.head

        Just zip ->
            let
                headLength =
                    Array.length buffer.head

                tailLength =
                    Array.length zip.tail

                tailStart =
                    zip.at + 1

                s1 =
                    if intersects from to 0 headLength then
                        Array.slice
                            (max 0 from)
                            (min headLength to)
                            buffer.head

                    else
                        Array.empty

                s2 =
                    if zip.at >= from && zip.at < to then
                        Array.push (buffer.fromFocus (Array.get (zip.at - 1) buffer.head) zip.val) s1

                    else
                        s1

                s3 =
                    if intersects from to tailStart (tailLength + tailStart) then
                        Array.append
                            s2
                            (Array.slice
                                (max 0 (from - tailStart))
                                (min tailLength (to - tailStart))
                                zip.tail
                            )

                    else
                        s2
            in
            s3


{-| If the buffer has a current focus point, its position and the data element at it
are returned.
-}
currentFocus : GapBuffer a b -> Maybe ( Int, b )
currentFocus buffer =
    buffer.zip
        |> Maybe.map (\{ at, val } -> ( at, val ))



-- Manipulate


{-| Sets the value as the focus of the `GapBuffer`.
If the `GapBuffer` was already focussed at a different index, that index will be
de-focussed, and the focus shifted to the specified index.

Note that de-focussing and re-focussing the `GapBuffer` will use the `toFocus` and
`fromFocus` functions that were specified when creating the buffer.

-}
setFocus : Int -> b -> GapBuffer a b -> GapBuffer a b
setFocus idx val buffer =
    let
        rezipped =
            focusAt idx buffer
    in
    { rezipped | zip = rezipped.zip |> Maybe.map (\zip -> { zip | val = val }) }


{-| Inserts an entry at the specified index into the buffer.If the GapBuffer was already
focussed at a different index, that index will be de-focussed, and the focus shifted to
the specified index. Entries at higher indexes will now have an index one higher than before.

Note that de-focussing and re-focussing the GapBuffer will use the toFocus and fromFocus
functions that were specified when creating the buffer.

If the index is out of range for the buffer this operation will do nothing.

-}
insertAtFocus : Int -> b -> GapBuffer a b -> GapBuffer a b
insertAtFocus idx val buffer =
    if idx < 0 || idx > buffer.length then
        buffer

    else
        { buffer
            | head = slice 0 idx buffer
            , zip =
                { val = val
                , at = idx
                , tail = slice idx buffer.length buffer
                }
                    |> Just
            , length = buffer.length + 1
        }


{-| Gets the value at the specified focus of the `GapBuffer`. If the `GapBuffer` was
already focussed at a different index, that index will be de-focussed, and the
focus shifted to the specified index.

Note that de-focussing and re-focussing the `GapBuffer` will use the `toFocus` and
`fromFocus` functions that were specified when creating the buffer.

-}
getFocus : Int -> GapBuffer a b -> ( GapBuffer a b, Maybe b )
getFocus idx buffer =
    let
        rezipped =
            focusAt idx buffer
    in
    ( rezipped, rezipped.zip |> Maybe.map .val )


{-| Update the value at the specified focus of the `GapBuffer`. If the `GapBuffer` was
already focussed at a different index, that index will be de-focussed, and the
focus shifted to the specified index.

Note that de-focussing and re-focussing the `GapBuffer` will use the `toFocus` and
`fromFocus` functions that were specified when creating the buffer.

-}
updateFocus : Int -> (b -> b) -> GapBuffer a b -> GapBuffer a b
updateFocus idx fn buffer =
    let
        rezipped =
            focusAt idx buffer
    in
    { rezipped | zip = rezipped.zip |> Maybe.map (\zip -> { zip | val = fn zip.val }) }


{-| Focusses the buffer at the specified index. If the GapBuffer was already focussed at
a different index, that index will be de-focussed, and the focus shifted to the specified
index.

Note that de-focussing and re-focussing the GapBuffer will use the toFocus and fromFocus
functions that were specified when creating the buffer.

If the index is out of range for the buffer this operation clamp the index to the available
range. Negative values will set the focus to zero. Values greater than the buffer length will
be off the end of the buffer, so no focus will be set.

-}
focusAt : Int -> GapBuffer a b -> GapBuffer a b
focusAt idx buffer =
    if idx < 0 then
        rezip 0 buffer

    else if idx >= buffer.length then
        rezip buffer.length buffer

    else
        case buffer.zip of
            Nothing ->
                rezip idx buffer

            Just zip ->
                if zip.at == idx then
                    buffer

                else
                    rezip idx buffer


{-| Deletes the specified index from the buffer. If the GapBuffer was already focussed at
a different index, that index will be de-focussed, and the focus shifted to the specified
index. Entries at higher indexes will now have an index one less than before.

Note that de-focussing and re-focussing the GapBuffer will use the toFocus and fromFocus
functions that were specified when creating the buffer.

If the index is out of range for the buffer this operation will do nothing.

-}
delete : Int -> GapBuffer a b -> GapBuffer a b
delete idx buffer =
    case get idx buffer of
        Nothing ->
            buffer

        Just _ ->
            { buffer
                | head = slice 0 idx buffer
                , zip =
                    get (idx + 1) buffer
                        |> Maybe.map
                            (\val ->
                                { val = buffer.toFocus val
                                , at = idx
                                , tail = slice (idx + 2) buffer.length buffer
                                }
                            )
                , length = buffer.length - 1
            }


{-| Advances the focus by 1. If there is no focus becuase it fell off the end
this returns nothing.

A function is supplied that can optionally map the entry at the current focus
into a new entry. If this mapping returns Nothing, then the focus is advanced.
If this mapping returns a value, the focus is not advanced and the new entry
replaces the one at the current focus. This feature can be used to stack
`advanceFocus` functions together over `GapBuffers` of `GapBuffers` of ...

-}
advanceFocus : (b -> Maybe b) -> GapBuffer a b -> Maybe (GapBuffer a b)
advanceFocus nextFn buffer =
    let
        focus =
            currentFocus buffer
    in
    case focus of
        Nothing ->
            Nothing

        Just ( idx, innerElement ) ->
            case nextFn innerElement of
                Nothing ->
                    focusAt (idx + 1) buffer
                        |> Just

                Just replacementInnerElement ->
                    setFocus idx replacementInnerElement buffer
                        |> Just



-- Rippling


{-| The possible outcomes of ripple operations.

A ripple is an operation which can complete all the way to the end of the buffer,
or can be stopped when it reaches a certain point from which it can be continued.

-}
type RippleOutcome
    = Done
    | StoppedAt Int


{-| Rippling runs the buffer focus between a 'from' index and a 'to' index. Each entry encountered is
extracted from the buffer and re-merged into the buffer by passing it through its 'toFocus' and
'fromFocus' functions.

This can be used to apply an operation such as formatting the text correctly, but only within a window
of the buffer. For example, in an editor working on 1 million lines, a change on an earlier line my
change the formatting on later lines, but we only want to apply the formatting on lines that the user
can currently see, or the operation will be too slow.

Since we know where a ripply operation ended, it can be re-run from that point. Or ripple operations can
be cancelled if they are overtaking by other ripple operations.

-}
ripple :
    Int
    -> Int
    -> (a -> a -> Bool)
    -> GapBuffer a b
    -> ( GapBuffer a b, RippleOutcome )
ripple from to contFn lines =
    let
        focussedBuffer =
            focusAt from lines
    in
    case focussedBuffer.zip of
        Nothing ->
            ( lines, Done )

        Just zip ->
            if zip.at /= from then
                ( lines, Done )

            else
                let
                    ( rippledTail, outcome ) =
                        rippleTail
                            0
                            (to - zip.at)
                            contFn
                            lines.toFocus
                            lines.fromFocus
                            (lines.fromFocus (Array.get (from - 1) focussedBuffer.head) zip.val)
                            zip.tail
                in
                ( { focussedBuffer
                    | zip =
                        Just
                            { at = zip.at
                            , val = zip.val
                            , tail = rippledTail
                            }
                  }
                , case outcome of
                    Done ->
                        Done

                    StoppedAt stop ->
                        if stop + zip.at >= lines.length - 1 then
                            Done

                        else
                            stop + zip.at |> StoppedAt
                )


rippleTail :
    Int
    -> Int
    -> (a -> a -> Bool)
    -> (a -> b)
    -> (Maybe a -> b -> a)
    -> a
    -> Array a
    -> ( Array a, RippleOutcome )
rippleTail idx to contFn toFocus fromFocus prevLine tail =
    if idx == to then
        ( tail, StoppedAt idx )

    else
        case Array.get idx tail of
            Nothing ->
                ( tail, Done )

            Just currentLine ->
                if contFn prevLine currentLine then
                    let
                        rippledLine =
                            toFocus currentLine
                                |> fromFocus (Just prevLine)
                    in
                    rippleTail (idx + 1)
                        to
                        contFn
                        toFocus
                        fromFocus
                        rippledLine
                        (Array.set idx rippledLine tail)

                else
                    ( tail, Done )



-- Iterate


{-| Iterates forward over a region of the buffer.

This is the most efficient way to extract and map data from the buffer. For
example, you would use this when rendering the visible contents of a `GapBuffer`
to Html. The implementation does not create intermediate data structures to hold
the extracted elements, and it only iterates over the range you specify.

-}
foldlSlice : (Int -> a -> acc -> acc) -> acc -> Int -> Int -> GapBuffer a b -> acc
foldlSlice fn acc from to buffer =
    List.foldl
        (\idx resAcc ->
            case get idx buffer of
                Just val ->
                    fn idx val resAcc

                Nothing ->
                    resAcc
        )
        acc
        (List.range from to)


{-| Iterates backward over a region of the buffer.

This is the most efficient way to extract and map data from the buffer. For
example, you would use this when rendering the visible contents of a `GapBuffer`
to Html. The implementation does not create intermediate data structures to hold
the extracted elements, and it only iterates over the range you specify.

-}
foldrSlice : (Int -> a -> acc -> acc) -> acc -> Int -> Int -> GapBuffer a b -> acc
foldrSlice fn acc from to buffer =
    List.foldr
        (\idx resAcc ->
            case get idx buffer of
                Just val ->
                    fn idx val resAcc

                Nothing ->
                    resAcc
        )
        acc
        (List.range from to)


{-| Iterates forward over the whole buffer.

This is the most efficient way to extract and map data from the buffer. For
example, you would use this when rendering the visible contents of a `GapBuffer`
to Html. The implementation does not create intermediate data structures to hold
the extracted elements, and it only iterates over the range you specify.

-}
indexedFoldl : (Int -> a -> acc -> acc) -> acc -> GapBuffer a b -> acc
indexedFoldl fn acc buffer =
    List.foldl
        (\idx resAcc ->
            case get idx buffer of
                Just val ->
                    fn idx val resAcc

                Nothing ->
                    resAcc
        )
        acc
        (List.range 0 buffer.length)


{-| Iterates backward over the whole buffer.

This is the most efficient way to extract and map data from the buffer. For
example, you would use this when rendering the visible contents of a `GapBuffer`
to Html. The implementation does not create intermediate data structures to hold
the extracted elements, and it only iterates over the range you specify.

-}
indexedFoldr : (Int -> a -> acc -> acc) -> acc -> GapBuffer a b -> acc
indexedFoldr fn acc buffer =
    List.foldr
        (\idx resAcc ->
            case get idx buffer of
                Just val ->
                    fn idx val resAcc

                Nothing ->
                    resAcc
        )
        acc
        (List.range 0 buffer.length)
