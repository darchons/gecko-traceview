# jshint devel:true

re_grouping = /\D+|\d+(\.\d+)?[ETGMkmμnpf]?/g

# Smart comparison function used with Array.prototype.sort. It is able to compare numbers
# and suffixes by value rather than by character. For example, '1MB' will come before '1GB',
# and 'v10' will come after 'v9'.
smartSort = (str1, str2) ->
    match1 = (str1 + '').match re_grouping
    match2 = (str2 + '').match re_grouping

    for i in [0...Math.min match1.length, match2.length]
        if !isNaN(parseInt match1[i]) and !isNaN(parseInt match2[i])
            diff = revSmartPrefix(match1[i]) - revSmartPrefix(match2[i])
            return diff if diff != 0
            continue
        m1 = match1[i].toUpperCase()
        m2 = match2[i].toUpperCase()
        return -1 if m1 < m2
        return 1 if m1 > m2

    match1.length - match2.length

# Same as smartSort but reversed
revSmartSort = (str1, str2) -> (-smartSort str1, str2)

_smartUnits = (values, names, precisions) ->
    (value) ->
        for i in [0...values.length]
            continue if value < values[i]
            return (value / values[i]).toPrecision(
                precisions[Math.min precisions.length - 1, i]) + names[i]
        value.toPrecision precisions[precisions.length - 1]

_revSmartUnits = (values, names) ->
    (value) ->
        value = value + ''
        for i in [0...values.length]
            continue if value.indexOf(names[i], value.length - names[i].length) < 0
            return +(value.slice 0, value.length - names[i].length) * values[i]
        parseFloat value

# Format a floating-point number by adding the appropriate SI-prefix and rounding to
# appropriate digits. e.g. smartPrefix(0.001) === '1m'
smartPrefix = _smartUnits(
    [1e15, 1e12, 1e9, 1e6, 1e3, 1, 1e-3, 1e-6, 1e-9, 1e-12, 1e-15]
    ['E', 'T', 'G', 'M', 'k', '', 'm', 'μ', 'n', 'p', 'f', '']
    [3])

# Parse a string of a number with SI-prefix into its equivalent floating-point number.
# e.g. revSmartPrefix('1m') === 0.001
revSmartPrefix = _revSmartUnits(
    [1e15, 1e12, 1e9, 1e6, 1e3, 1e-3, 1e-6, 1e-9, 1e-12, 1e-15, 1]
    ['E', 'T', 'G', 'M', 'k', 'm', 'μ', 'n', 'p', 'f', ''])

# Format a number of seconds into appropriate time units. e.g. smartTime(3600) === '1h'
smartTime = _smartUnits(
    [31556952, 604800, 86400, 3600, 60, 1, 1e-3, 1e-6, 1e-9, 1e-12]
    ['y', 'w', 'd', 'h', 'm', 's', 'ms', 'μs', 'ns', 'ps', '']
    [2, 2, 2, 2, 2, 2, 3])

# Format a fraction number into a percentage. e.g. smartPercent(0.1) === '10.0%'
smartPercent = (v) -> ((v * 100).toPrecision(3) + "%")

binarySearch = (arr, value, fn) ->
    fn ?= (v) -> v
    [lo, hi] = [0, arr.length]
    i = Math.floor (lo + hi) / 2
    [iv, ivp1] = [fn(arr[i]), fn(arr[i + 1])]
    until iv < value and not (ivp1 < value)
        lo = i + 1 if ivp1 < value
        hi = i if not (iv < value)
        return hi if lo >= hi
        i = Math.floor (lo + hi) / 2
        [iv, ivp1] = [fn(arr[i]), fn(arr[i + 1])]
    i + 1

escapeHTML = (str) -> (str && str.replace(/</g, "&lt;").replace(/>/g, "&gt;"))

drawn_frames = []

getLabel = (trace, idx) ->
    label = trace.strings[idx]
    lpar = label.lastIndexOf "("
    slash = label.lastIndexOf "/"
    colon = label.lastIndexOf ":"
    if lpar >= 0 and slash > lpar and colon > slash
        # method (file:line)
        return label[...lpar + 1] + label[slash + 1...]
    else if lpar < 0 and slash >= 0 and colon > slash
        # file:line
        return label[slash + 1...]
    label

process = (elems, trace, thread) ->
    slider = elems.slider
    table = elems.table
    min = thread.times[0]
    max = thread.times[thread.times.length - 1]

    slider.rangeSlider
        bounds:
            min: min
            max: max
        defaultValues:
            min: min
            max: max
        range:
            min: 15 * (max - min) / slider.width()
        formatter: (value) -> (Math.round(value) + "ms")
        valueLabels: "change"

    stack = []
    labels = []
    stats = {}

    for i in [0...thread.labels.length]
        [prevTime, time] = [time, thread.times[i]]

        label = getLabel trace, thread.labels[i]
        prevLabel = if label.length then stack[stack.length - 1] else stack.pop()
        stack.push label if label.length

        if not prevLabel?
            continue

        if not stats[prevLabel]?
            labels.push prevLabel
            stats[prevLabel] =
                count: if label.length then 0 else 1
                time: time - prevTime
            continue

        stats[prevLabel].count++ if not label.length
        stats[prevLabel].time += time - prevTime

    for label in stack
        stats[label].count++

    for label, i in labels
        stat = stats[label]
        table.append(
            $("<tr/>").append(
                $("<td/>").text label
                $("<td/>").text stat.count
                $("<td/>").text (stat.time / stat.count).toFixed(3)
                $("<td/>").text stat.time.toFixed(3)
            ))

    $.bootstrapSortable()

redraw = (elems, trace, thread, range) ->
    plot = elems.plot
    min = range.min # time at start of view
    duration = range.max - range.min # time duration inside view
    start = binarySearch thread.times, min # index of frame that first starts in view
    end = binarySearch thread.times, range.max # index of frame that last ends in view

    WIDTH = plot.width()
    HEIGHT = plot.height()
    FRAME_STRIDE = HEIGHT / 25
    FRAME_HEIGHT = FRAME_STRIDE * 0.8
    MIN_FRAME_WIDTH = 4 / WIDTH

    ctx = plot.clearCanvas()

    # ruler_scale = Math.pow 10, "#{Math.floor 50 * duration / WIDTH}".length
    # ruler_start = ruler_scale * Math.ceil(min / ruler_scale) - min
    # for i in [ruler_start...duration] by ruler_scale
    #     x = i / duration * WIDTH
    #     ctx.drawText
    #         x: x
    #         y: 10
    #         fillStyle: "#aaa"
    #         strokeWidth: 0
    #         fontSize: "0.8em"
    #         text: "#{Math.round i + min}ms"
    #         fromCenter: true
    #         maxWidth: 1000
    #     ctx.drawLine
    #         strokeStyle: '#aaa'
    #         strokeWidth: 1
    #         x1: x
    #         y1: 20
    #         x2: x
    #         y2: HEIGHT

    active_stack = [] # unfinished frames
    active_count = 0 # number of active frames in active_stack
    mergeable_frames = [] # finished frames waiting to be merged
    drawn_frames = []

    _drawFrame = (frame) ->
        x = WIDTH * frame.left
        y = HEIGHT - (frame.top + 1) * FRAME_STRIDE
        width = WIDTH * (frame.right - frame.left)
        height = FRAME_HEIGHT
        color = chroma.hsl(
            222 - 222 * Math.atan((frame.multiplicity or 0) / 20) * 2 / Math.PI, 0.55, 0.55)
        label = frame.label

        ctx.drawRect
            x: x
            y: y
            width: width
            height: height
            fillStyle: color.hex()
            strokeWidth: 1
            strokeStyle: color.darken().hex()
            fromCenter: false

        drawn_frames.push
            left: x
            right: x + width
            top: y
            bottom: y + height
            label: label
            labels: frame.labels
            multiplicity: frame.multiplicity
            duration: Math.round (frame.right - frame.left) * duration

        if not frame.multiplicity and width > 4 * MIN_FRAME_WIDTH
            textOptions =
                x: x
                y: y
                fillStyle: "#fff"
                strokeWidth: 0
                fontSize: "1em"
                text: label
                fromCenter: false
                maxWidth: 1000
            textDims = ctx.measureText textOptions
            if textDims.width + 2 * MIN_FRAME_WIDTH <= width
                textOptions.x += (width - textDims.width) / 2
                textOptions.y += (height - textDims.height) / 2
                ctx.drawText textOptions

    # prefill with frames that started to the left of view
    for i in [0...start] by 1
        label = getLabel trace, thread.labels[i]
        if not label.length
            # popping a frame; discard from active stack
            active_count--
            continue
        # pushing an unfinished frame
        active_stack.push null while active_count >= active_stack.length
        active_stack[active_count] =
            label: label
            left: 0
            right: 0
            top: active_count
        active_count++

    # draw frames within view
    for i in [start...end] by 1
        label = getLabel trace, thread.labels[i]
        pos = (thread.times[i] - min) / duration
        if label.length
            # push an unfinished frame onto stack
            active_stack.push null while active_count >= active_stack.length
            active_stack[active_count] =
                label: label
                left: pos
                right: 0
                top: active_count
            active_count++
            continue

        # popping a frame; finish the frame
        active_count--
        frame = active_stack[active_count]
        frame.right = pos

        if pos - frame.left < MIN_FRAME_WIDTH
            # save for merging later
            mergeable_frames.push null while active_count >= mergeable_frames.length
            merger = mergeable_frames[active_count]
            if frame.left - merger?.right < MIN_FRAME_WIDTH
                # merge with previous frame
                merger.right = pos
                merger.multiplicity = (merger.multiplicity or 1) + 1
                merger.labels[frame.label] = (merger.labels[frame.label] or 0) + 1
                continue

            if merger and merger.right - merger.left >= MIN_FRAME_WIDTH
                # draw the previous merged frame
                _drawFrame merger

            frame.labels = {}
            frame.labels[frame.label] = 1
            # replace previous unmerged frame
            mergeable_frames[active_count] = frame
            continue

        # draw now
        _drawFrame frame

    # finish all remaining frames
    for merger in mergeable_frames
        if merger and merger.right - merger.left >= MIN_FRAME_WIDTH
            _drawFrame merger

    while active_count-- > 0
        frame = active_stack[active_count]
        frame.right = 1
        _drawFrame frame

    drawn_frames.sort (a, b) -> a.right - b.right

initialize = (trace, thread) ->
    elems =
        container: $(".traceview .plot-container")
        plot: $(".traceview .plot")
        tooltip: $(".traceview .tooltip")
        marker: $(".traceview .marker")
        timestamp: $(".traceview .marker .timestamp")
        slider: $(".traceview .slider")
        table: $(".stats tbody")
    elems.plot.attr "width", elems.slider.width() # also clears the canvas
    elems.marker.height elems.plot.height()

    dragging = null

    process elems, trace, thread
    redraw elems, trace, thread, elems.slider.rangeSlider "values"
    elems.slider.on "valuesChanging", (e, data) ->
        window.requestAnimationFrame () ->
            dragging = null
            elems.marker.hide()
            elems.marker.width 1
            redraw elems, trace, thread, data.values

    mousemove = (e) ->
        TOOLTIP_SPACING = 10
        plotOffset = elems.plot.offset()
        [x, y] = [e.pageX - plotOffset.left, e.pageY - plotOffset.top]
        start = binarySearch drawn_frames, x, (f) -> f?.right
        range = elems.slider.rangeSlider "values"

        if dragging and not dragging.stopped
            dragging_width = Math.abs e.pageX - dragging.x
            elems.timestamp.text "<#{Math.round(dragging_width / elems.plot.width() *
                                     (range.max - range.min))}ms>"
            elems.marker.width Math.max(1, dragging_width)
            elems.marker.offset
                left: Math.min e.pageX, dragging.x
                top: plotOffset.top
            return

        if not dragging?.stopped
            elems.timestamp.text "#{Math.round(x / elems.plot.width() *
                                    (range.max - range.min) + range.min)}ms"
            elems.marker.show().offset
                left: e.pageX
                top: plotOffset.top

        for i in [start...drawn_frames.length] by 1
            frame = drawn_frames[i]
            if x <= frame.left or y <= frame.top or y > frame.bottom
                continue

            if frame.labels
                label = "#{frame.multiplicity} labels<br>"
                labels = Object.keys frame.labels
                labels.sort (a, b) ->
                    frame.labels[b] - frame.labels[a]
                label += ("#{frame.labels[l]}&times; " +
                          escapeHTML(l) for l in labels[...3]).join '<br>'
            else
                label = escapeHTML(frame.label)
            label += "<br>spanning #{frame.duration}ms"

            elems.tooltip.children(".tooltip-inner").html label
            elems.tooltip.show().offset(
                left: Math.max(TOOLTIP_SPACING,
                    Math.min(elems.plot.width() - elems.tooltip.width(),
                    plotOffset.left + (frame.right + frame.left - elems.tooltip.width()) / 2))
                top: plotOffset.top + frame.top - elems.tooltip.height() - TOOLTIP_SPACING)
            return

        elems.tooltip.hide()

    mouseout = (e) ->
        elems.tooltip.hide()
        if dragging
            dragging.stopped = true
            return
        elems.marker.hide()

    mousedown = (e) ->
        if elems.tooltip.is(':visible')
            return
        dragging =
            x: e.pageX
            y: e.pageY
        mousemove e
        e.preventDefault()

    mouseup = (e) ->
        if not dragging
            return
        if Math.abs(e.pageX - dragging.x) < 2 and Math.abs(e.pageY - dragging.y) < 2
            dragging = null
            mousemove e
            return
        dragging.stopped = true

    elems.container.mousemove mousemove
    elems.container.mouseleave mouseout
    elems.container.mousedown mousedown
    elems.container.mouseup mouseup

$ ->
    tracefile = $("#tracefile")
    tracefile.change () ->
        $.getJSON tracefile.val()
            .done (file) -> initialize(file, file.trace[0])
    tracefile.trigger "change"
