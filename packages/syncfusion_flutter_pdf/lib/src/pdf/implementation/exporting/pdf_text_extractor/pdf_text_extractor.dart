import 'dart:ui';

import 'package:syncfusion_flutter_pdf/src/pdf/implementation/pages/pdf_page_layer_collection.dart';

import '../../../interfaces/pdf_interface.dart';
import '../../graphics/fonts/enums.dart';
import '../../graphics/fonts/pdf_cjk_standard_font.dart';
import '../../graphics/fonts/pdf_font.dart';
import '../../graphics/fonts/pdf_standard_font.dart';
import '../../io/pdf_constants.dart';
import '../../pages/enum.dart';
import '../../pages/pdf_page.dart';
import '../../pdf_document/pdf_document.dart';
import '../../primitives/pdf_array.dart';
import '../../primitives/pdf_dictionary.dart';
import '../../primitives/pdf_reference_holder.dart';
import '../../primitives/pdf_stream.dart';
import 'enums.dart';
import 'font_structure.dart';
import 'glyph.dart';
import 'image_renderer.dart';
import 'matched_item.dart';
import 'matrix_helper.dart';
import 'page_resource_loader.dart';
import 'parser/content_parser.dart';
import 'text_element.dart';
import 'text_glyph.dart';
import 'text_line.dart';
import 'text_word.dart';
import 'xobject_element.dart';

/// Represents a text extractor from an existing PDF document
class PdfTextExtractor {
  //Constructor
  /// Initialize a new instance of the [PdfTextExtractor] class
  /// from the instance of [PdfDocument]
  ///
  /// ```dart
  /// //Load an exisiting PDF document.
  /// PdfDocument document = PdfDocument.fromBase64String(pdfData);
  /// //Extract text from all pages
  /// String text = PdfTextExtractor(document).extractText();
  /// //Dispose the document.
  /// document.dispose();
  /// ```
  PdfTextExtractor(PdfDocument document) {
    if (!PdfDocumentHelper.getHelper(document).isLoadedDocument) {
      ArgumentError.value(document, 'document',
          'document instance is not a loaded PDF document');
    }
    _document = document;
    _initialize();
  }

  //Fields
  late PdfDocument _document;
  late List<String> _symbolChars;
  String? _currentFont;
  double? _fontSize;
  PdfPage? _currentPage;
  late PageResourceLoader _resourceLoader;
  late int _currentPageIndex;
  bool _isLayout = false;
  double _characterSpacing = 0;
  double _wordSpacing = 0;
  MatrixHelper? _textLineMatrix;
  MatrixHelper? _textMatrix;
  MatrixHelper? _currentTextMatrix;
  Rect? _tempBoundingRectangle;
  bool _hasLeading = false;
  late MatrixHelper _currentTransformationMatrix;
  bool _hasBDC = false;

  //Public methods
  /// Extract text from an existing PDF document
  ///
  /// startPageIndex and endPageIndex specifies the page range to be selected
  /// to extract text.
  /// for example, startPageIndex is 0 and endPageIndex is 9
  /// is used to extract text from first page to 10 page of loaded PDF
  ///
  /// for extracting text from particular page,
  /// we can set an index of the page to startPageIndex
  ///
  /// ```dart
  /// //Load an exisiting PDF document.
  /// PdfDocument document = PdfDocument.fromBase64String(pdfData);
  /// //Extract text from all pages
  /// String text = PdfTextExtractor(document).extractText();
  /// //Dispose the document.
  /// document.dispose();
  /// ```
  String extractText(
      {int? startPageIndex, int? endPageIndex, bool? layoutText}) {
    _isLayout = layoutText ?? false;
    return _extractText(startPageIndex, endPageIndex);
  }

  /// Extract [TextLine] from an existing PDF document
  ///
  /// startPageIndex and endPageIndex specifies the page range to be selected
  /// to extract text line.
  /// for example, startPageIndex is 0 and endPageIndex is 9
  /// is used to extract text line from first page to 10 page of loaded PDF
  ///
  /// for extracting text line from particular page,
  /// we can set an index of the page to startPageIndex
  ///
  /// ```dart
  /// //Load an exisiting PDF document.
  /// PdfDocument document = PdfDocument.fromBase64String(pdfData);
  /// //Extract text from all pages
  /// List<TextLine> textLine = PdfTextExtractor(document).extractTextLines();
  /// //Dispose the document.
  /// document.dispose();
  /// ```
  List<TextLine> extractTextLines({int? startPageIndex, int? endPageIndex}) {
    return _extractTextLines(startPageIndex, endPageIndex);
  }

  /// Returns the information of the matched texts in a specific page
  /// based on the list of string to be searched
  ///
  /// startPageIndex and endPageIndex specifies the page range to be selected
  /// to find text.
  /// for example, startPageIndex is 0 and endPageIndex is 9
  /// is used to find text from first page to 10 page of loaded PDF
  ///
  /// for finding text and get matched item from particular page,
  /// we can set an index of the page to startPageIndex
  ///
  /// search option defines the constants that specify the option
  /// for text search
  ///
  /// ```dart
  /// //Load an exisiting PDF document.
  /// PdfDocument document = PdfDocument.fromBase64String(pdfData);
  /// //list of string to be searched.
  /// List<String> searchString = <String>['text1', 'text2'];
  /// //Find text and get matched items.
  /// List<MatchedItem> textLine = PdfTextExtractor(document).findText(searchString);
  /// //Dispose the document.
  /// document.dispose();
  /// ```
  List<MatchedItem> findText(List<String> searchString,
      {int? startPageIndex,
      int? endPageIndex,
      TextSearchOption? searchOption}) {
    return _findText(searchString, startPageIndex, endPageIndex, searchOption);
  }

  //Implementation
  void _checkPageNumber(int pageNumber) {
    if (pageNumber < 0 || pageNumber >= _document.pages.count) {
      throw ArgumentError.value(pageNumber, 'pageNumber', 'Index out of range');
    }
  }

  void _initialize() {
    _symbolChars = <String>['(', ')', '[', ']', '<', '>'];
    _resourceLoader = PageResourceLoader();
    _currentTextMatrix = MatrixHelper(0, 0, 0, 0, 0, 0);
    _textLineMatrix = MatrixHelper(0, 0, 0, 0, 0, 0);
    _textMatrix = MatrixHelper(0, 0, 0, 0, 0, 0);
    _tempBoundingRectangle = Rect.zero;
    _currentTransformationMatrix = MatrixHelper(1, 0, 0, 1, 0, 0);
  }

  String _extractText(int? startPageIndex, int? endPageIndex) {
    if (startPageIndex == null) {
      if (endPageIndex != null) {
        throw ArgumentError.value(endPageIndex, 'endPageIndex',
            'Invalid argument. start page index cannot be null');
      } else {
        return _extractTextFromRange(0, _document.pages.count - 1);
      }
    } else if (endPageIndex == null) {
      _checkPageNumber(startPageIndex);
      _currentPageIndex = startPageIndex;
      return _getText(_document.pages[startPageIndex]);
    } else {
      _checkPageNumber(startPageIndex);
      _checkPageNumber(endPageIndex);
      return _extractTextFromRange(startPageIndex, endPageIndex);
    }
  }

  List<TextLine> _extractTextLines(int? startPageIndex, int? endPageIndex) {
    if (startPageIndex == null) {
      if (endPageIndex != null) {
        throw ArgumentError.value(endPageIndex, 'endPageIndex',
            'Invalid argument. start page index cannot be null');
      } else {
        return _extractTextLineFromRange(0, _document.pages.count - 1);
      }
    } else if (endPageIndex == null) {
      _checkPageNumber(startPageIndex);
      _currentPageIndex = startPageIndex;
      return _getTextLine(_document.pages[startPageIndex]);
    } else {
      _checkPageNumber(startPageIndex);
      _checkPageNumber(endPageIndex);
      return _extractTextLineFromRange(startPageIndex, endPageIndex);
    }
  }

  List<MatchedItem> _findText(List<String> searchString, int? startPageIndex,
      int? endPageIndex, TextSearchOption? searchOption) {
    if (startPageIndex == null) {
      if (endPageIndex != null) {
        throw ArgumentError.value(endPageIndex, 'endPageIndex',
            'Invalid argument. start page index cannot be null');
      } else {
        return _findTextFromRange(
            0, _document.pages.count - 1, searchString, searchOption);
      }
    } else if (endPageIndex == null) {
      _checkPageNumber(startPageIndex);
      _currentPageIndex = startPageIndex;
      return _searchInBackground(
          _document.pages[startPageIndex], searchString, searchOption);
    } else {
      _checkPageNumber(startPageIndex);
      _checkPageNumber(endPageIndex);
      return _findTextFromRange(
          startPageIndex, endPageIndex, searchString, searchOption);
    }
  }

  String _extractTextFromRange(int startPageIndex, int endPageIndex) {
    String resultText = '';
    for (int i = startPageIndex; i <= endPageIndex; i++) {
      final String text = _getText(_document.pages[i]);
      resultText = resultText + (i > startPageIndex ? '\r\n' : '') + text;
    }
    return resultText;
  }

  List<TextLine> _extractTextLineFromRange(
      int startPageIndex, int endPageIndex) {
    final List<TextLine> result = <TextLine>[];
    for (int i = startPageIndex; i <= endPageIndex; i++) {
      _currentPageIndex = i;
      final List<TextLine> textLines = _getTextLine(_document.pages[i]);
      if (textLines.isNotEmpty) {
        result.addAll(textLines);
      }
    }
    return result;
  }

  List<MatchedItem> _findTextFromRange(int startPageIndex, int endPageIndex,
      List<String> searchString, TextSearchOption? searchOption) {
    final List<MatchedItem> result = <MatchedItem>[];
    for (int i = startPageIndex; i <= endPageIndex; i++) {
      _currentPageIndex = i;
      final List<MatchedItem> textLines =
          _searchInBackground(_document.pages[i], searchString, searchOption);
      if (textLines.isNotEmpty) {
        result.addAll(textLines);
      }
    }
    return result;
  }

  String _getText(PdfPage page) {
    _currentPage = page;
    _fontSize = 0;
    PdfPageHelper.getHelper(page).isTextExtraction = true;
    final bool isChanged = _checkPageDictionary(page);
    final bool isContentChanged = _checkContentArray(page);
    final PdfRecordCollection? recordCollection = _getRecordCollection(page);
    final PdfPageResources pageResources =
        _resourceLoader.getPageResources(page);
    String resultantText = _isLayout
        ? _renderTextAsLayout(recordCollection, pageResources)
        : _renderText(recordCollection, pageResources);
    if (recordCollection != null) {
      recordCollection.recordCollection.clear();
    }
    pageResources.resources.clear();
    if (pageResources.fontCollection.isNotEmpty) {
      pageResources.fontCollection.clear();
    }
    if (resultantText != '') {
      resultantText = _skipEscapeSequence(resultantText);
    }
    PdfPageHelper.getHelper(page).contents.changed = isContentChanged;
    PdfPageHelper.getHelper(page).dictionary!.changed = isChanged;
    PdfPageHelper.getHelper(page).isTextExtraction = false;
    return resultantText;
  }

  List<TextLine> _getTextLine(PdfPage pdfPage) {
    final List<TextLine> result = <TextLine>[];
    _currentPage = pdfPage;
    _fontSize = 0;
    PdfPageHelper.getHelper(pdfPage).isTextExtraction = true;
    final bool isChanged = _checkPageDictionary(pdfPage);
    final bool isContentChanged = _checkContentArray(pdfPage);
    final PdfRecordCollection? recordCollection = _getRecordCollection(pdfPage);
    final PdfPageResources pageResources =
        _resourceLoader.getPageResources(pdfPage);
    final ImageRenderer renderer = ImageRenderer(recordCollection,
        pageResources, pdfPage.size.height * 1.3333333333333333);
    renderer.isExtractLineCollection = true;
    final double rotation = _getPageRotation(pdfPage);
    renderer.pageRotation = rotation;
    renderer.renderAsImage();
    renderer.isExtractLineCollection = false;
    int i = 0;
    double? width = 0;
    double? height = 0;
    double? dx = 0;
    double? dy = 0;
    int offsetY = 0;
    double yPos = 0;
    String pagestring = '';
    int lineStartIndex = 0;
    TextLine textLine = TextLineHelper.initialize();
    if (pagestring == '') {
      for (final Glyph s in renderer.imageRenderGlyphList) {
        pagestring = pagestring + s.toUnicode;
      }
    }
    if (renderer.extractTextElement.isNotEmpty) {
      for (int k = 0; k < renderer.extractTextElement.length; k++) {
        bool hasRotation = false;
        if (i < renderer.imageRenderGlyphList.length) {
          final Glyph tempGlyph = renderer.imageRenderGlyphList[i];
          if (tempGlyph.isRotated && rotation == 270) {
            yPos = tempGlyph.boundingRect.left;
            hasRotation = true;
          } else {
            yPos = tempGlyph.boundingRect.top;
          }
          if ((i != 0 &&
                  yPos.toInt() != offsetY &&
                  renderer.extractTextElement[k].renderedText != '') ||
              (i == renderer.imageRenderGlyphList.length - 1)) {
            offsetY = yPos.toInt();
            if (textLine.wordCollection.isNotEmpty) {
              result.add(_prepareTextLine(
                  textLine, renderer, lineStartIndex, i, rotation));
            }
            lineStartIndex = i;
            textLine = TextLineHelper.initialize();
          }
          final TextElement textElement = renderer.extractTextElement[k];
          final List<String> words = textElement.renderedText.split(' ');
          textElement.text = ' ';
          TextWord? textwords;
          List<TextGlyph> glyphs = <TextGlyph>[];
          for (int x = 0; x < words.length; x++) {
            if (pagestring.contains(words[x]) && words[x].isNotEmpty) {
              glyphs = <TextGlyph>[];
              String tempText = '';
              int lastIndex = i;
              for (int m = i; m < i + words[x].length; m++) {
                final Glyph tempGlyph = renderer.imageRenderGlyphList[m];
                final Rect tempBounds = tempGlyph.boundingRect;
                final Rect glyphBounds = Rect.fromLTRB(tempBounds.left,
                    tempBounds.top, tempBounds.right, tempBounds.bottom);
                final TextGlyph textGlyph = TextGlyphHelper.initialize(
                    tempGlyph.toUnicode,
                    textElement.fontName,
                    textElement.fontStyle,
                    _calculateBounds(glyphBounds),
                    textElement.fontSize,
                    tempGlyph.isRotated);
                tempText += textGlyph.text;
                glyphs.add(textGlyph);
                lastIndex = m;
                if (words[x] == tempText) {
                  break;
                }
              }
              Rect? wordBound;
              dx = renderer.imageRenderGlyphList[i].boundingRect.left;
              dy = renderer.imageRenderGlyphList[i].boundingRect.top;
              if (hasRotation && rotation == 270) {
                width = renderer.imageRenderGlyphList[i].boundingRect.width;
                height = renderer
                    .imageRenderGlyphList[lastIndex].boundingRect.bottom;
                wordBound = Rect.fromLTWH(dx, dy, width, height - dy);
              } else {
                height = renderer.imageRenderGlyphList[i].boundingRect.height;
                if (dx >
                    renderer
                        .imageRenderGlyphList[lastIndex].boundingRect.left) {
                  width = (dx -
                          renderer.imageRenderGlyphList[lastIndex].boundingRect
                              .left) +
                      renderer
                          .imageRenderGlyphList[lastIndex].boundingRect.width;
                } else {
                  width = (renderer
                          .imageRenderGlyphList[lastIndex].boundingRect.left) +
                      renderer
                          .imageRenderGlyphList[lastIndex].boundingRect.width;
                }
                wordBound = Rect.fromLTWH(dx, dy, width - dx, height);
              }
              i = lastIndex + 1;
              textwords = TextWordHelper.initialize(
                  words[x],
                  textElement.fontName,
                  textElement.fontStyle,
                  glyphs,
                  wordBound,
                  textElement.fontSize);
              textLine.wordCollection.add(textwords);
            }
            textElement.text = words[x];
            if (textElement.text != '') {
              if (x < words.length - 1) {
                if (i != 0) {
                  final Map<String, dynamic> tempResult = _addSpace(textwords,
                      renderer, textElement, i, dx, dy, width, height);
                  dx = tempResult['dx'] as double?;
                  dy = tempResult['dy'] as double?;
                  width = tempResult['width'] as double?;
                  height = tempResult['height'] as double?;
                  textLine.wordCollection.add(tempResult['word']);
                }
                i = i + 1;
              }
              if (x < words.length - 1 &&
                  i <= renderer.imageRenderGlyphList.length - 1 &&
                  renderer.imageRenderGlyphList[i].toUnicode == ' ') {
                i = i + 1;
              }
            } else {
              if (i <= renderer.imageRenderGlyphList.length - 1) {
                if (x != words.length - 1 &&
                    renderer.imageRenderGlyphList[i].toUnicode == ' ') {
                  if (i != 0) {
                    final Map<String, dynamic> tempResult = _addSpace(textwords,
                        renderer, textElement, i, dx, dy, width, height);
                    dx = tempResult['dx'] as double?;
                    dy = tempResult['dy'] as double?;
                    width = tempResult['width'] as double?;
                    height = tempResult['height'] as double?;
                    textLine.wordCollection.add(tempResult['word']);
                  }
                  i = i + 1;
                }
              }
            }
          }
          if (i != 0 &&
                  yPos.toInt() != offsetY &&
                  renderer.extractTextElement[k].renderedText != '' &&
                  renderer.extractTextElement[k].renderedText != ' ' ||
              (i == renderer.imageRenderGlyphList.length - 1)) {
            if (renderer.extractTextElement.isNotEmpty && k == 0) {
              offsetY = yPos.toInt();
              if (textLine.wordCollection.isNotEmpty) {
                result.add(_prepareTextLine(
                    textLine, renderer, lineStartIndex, i, rotation));
              }
              lineStartIndex = i;
              textLine = TextLineHelper.initialize();
            }
          }
        }
      }
      final TextElement element =
          renderer.extractTextElement[renderer.extractTextElement.length - 1];
      if (textLine.wordCollection.isNotEmpty &&
          !result.contains(textLine) &&
          element.renderedText != '' &&
          element.renderedText != ' ') {
        result.add(
            _prepareTextLine(textLine, renderer, lineStartIndex, i, rotation));
        textLine = TextLineHelper.initialize();
      }
    }
    if (textLine.wordCollection.isNotEmpty && !result.contains(textLine)) {
      result.add(
          _prepareTextLine(textLine, renderer, lineStartIndex, i, rotation));
      textLine = TextLineHelper.initialize();
    }
    PdfPageHelper.getHelper(pdfPage).contents.changed = isContentChanged;
    PdfPageHelper.getHelper(pdfPage).dictionary!.changed = isChanged;
    PdfPageHelper.getHelper(pdfPage).isTextExtraction = false;
    return result;
  }

  List<MatchedItem> _searchInBackground(
      PdfPage page, List<String> searchString, TextSearchOption? searchOption) {
    final List<MatchedItem> result = <MatchedItem>[];
    final String pageText = _getText(page);
    if (pageText != '') {
      bool isMatched = false;
      for (int i = 0; i < searchString.length; i++) {
        final String term = searchString[i];
        if (searchOption != null &&
            (searchOption == TextSearchOption.caseSensitive ||
                searchOption == TextSearchOption.both)) {
          if (pageText.contains(term)) {
            isMatched = true;
            break;
          }
        } else if (pageText.toLowerCase().contains(term.toLowerCase())) {
          isMatched = true;
          break;
        }
      }
      if (isMatched) {
        _currentPage = page;
        _fontSize = 0;
        PdfPageHelper.getHelper(page).isTextExtraction = true;
        final bool isChanged = _checkPageDictionary(page);
        final bool isContentChanged = _checkContentArray(page);
        final PdfRecordCollection? recordCollection =
            _getRecordCollection(page);
        final PdfPageResources pageResources =
            _resourceLoader.getPageResources(page);
        final ImageRenderer renderer = ImageRenderer(recordCollection,
            pageResources, page.size.height * 1.3333333333333333);
        renderer.pageRotation = _getPageRotation(page);
        renderer.renderAsImage();
        String renderedString = '';
        final Map<int, int> combinedGlyphLength = <int, int>{};
        if (renderer.imageRenderGlyphList.isNotEmpty) {
          for (final Glyph glyph in renderer.imageRenderGlyphList) {
            final String currentText = glyph.toUnicode;
            if (currentText.length > 1) {
              combinedGlyphLength[renderedString.length] = currentText.length;
            }
            renderedString = renderedString + glyph.toUnicode;
          }
          if (renderedString != '') {
            final Map<String, List<int>> mappedIndexes = <String, List<int>>{};
            if (searchOption == null ||
                (searchOption != TextSearchOption.caseSensitive &&
                    searchOption != TextSearchOption.both)) {
              renderedString = renderedString.toLowerCase();
            }
            final int textLength = renderedString.length;
            for (final String term in searchString) {
              if (term != '' && !mappedIndexes.containsKey(term)) {
                final List<int> indexes = <int>[];
                final String currentText = (searchOption != null &&
                        (searchOption == TextSearchOption.caseSensitive ||
                            searchOption == TextSearchOption.both))
                    ? term
                    : term.toLowerCase();
                int startIndex = 0;
                final int length = currentText.length;
                while (startIndex <= textLength &&
                    renderedString.contains(currentText, startIndex)) {
                  int index = renderedString.indexOf(currentText, startIndex);
                  final int tempIndex = index;
                  if (searchOption != null &&
                      (searchOption == TextSearchOption.wholeWords ||
                          searchOption == TextSearchOption.both)) {
                    if (index == 0 ||
                        _hasEscapeCharacter(renderedString[index - 1])) {
                      if (index + length == textLength) {
                        if (combinedGlyphLength.isNotEmpty) {
                          index = _checkCombinedTextIndex(
                              index, combinedGlyphLength);
                        }
                        indexes.add(index);
                      } else if (_hasEscapeCharacter(
                          renderedString[index + length])) {
                        if (combinedGlyphLength.isNotEmpty) {
                          index = _checkCombinedTextIndex(
                              index, combinedGlyphLength);
                        }
                        indexes.add(index);
                      }
                    }
                  } else {
                    if (combinedGlyphLength.isNotEmpty) {
                      index =
                          _checkCombinedTextIndex(index, combinedGlyphLength);
                    }
                    indexes.add(index);
                  }
                  startIndex = tempIndex + 1;
                }
                if (indexes.isNotEmpty) {
                  for (final int index in indexes) {
                    final Rect rect = _calculatedTextounds(
                        renderer.imageRenderGlyphList, term, index, page);
                    result.add(MatchedItemHelper.initialize(
                        term, rect, _currentPageIndex));
                  }
                }
              }
            }
          }
        }
        PdfPageHelper.getHelper(page).contents.changed = isContentChanged;
        PdfPageHelper.getHelper(page).dictionary!.changed = isChanged;
        PdfPageHelper.getHelper(page).isTextExtraction = false;
      }
    }
    return result;
  }

  int _checkCombinedTextIndex(
      int textIndex, Map<int, int> combinedGlyphLength) {
    int adjustableLength = 0;
    combinedGlyphLength.forEach((int index, int length) {
      if (index < textIndex) {
        adjustableLength += length - 1;
      }
    });
    return textIndex - adjustableLength;
  }

  PdfRecordCollection? _getRecordCollection(PdfPage page) {
    PdfRecordCollection? recordCollection;
    final List<int>? combinedData =
        PdfPageLayerCollectionHelper.getHelper(page.layers)
            .combineContent(true);
    if (combinedData != null) {
      final ContentParser parser = ContentParser(combinedData);
      parser.isTextExtractionProcess = true;
      recordCollection = parser.readContent();
      parser.isTextExtractionProcess = false;
    }
    return recordCollection;
  }

  bool _checkPageDictionary(PdfPage page) {
    return PdfPageHelper.getHelper(page).dictionary!.changed != null &&
        PdfPageHelper.getHelper(page).dictionary!.changed!;
  }

  bool _checkContentArray(PdfPage page) {
    bool isContentChanged = false;
    if (PdfPageHelper.getHelper(page)
        .dictionary!
        .containsKey(PdfDictionaryProperties.contents)) {
      final IPdfPrimitive? contents = PdfPageHelper.getHelper(page)
          .dictionary![PdfDictionaryProperties.contents];
      if (contents is PdfReferenceHolder) {
        final PdfReferenceHolder holder = contents;
        final IPdfPrimitive? primitive = holder.object;
        if (primitive is PdfArray) {
          isContentChanged = primitive.changed!;
        } else if (primitive is PdfStream) {
          isContentChanged = primitive.changed!;
        }
      } else if (contents is PdfArray) {
        isContentChanged = contents.changed!;
      }
    }
    return isContentChanged;
  }

  Map<String, dynamic> _addSpace(
      TextWord? textwords,
      ImageRenderer renderer,
      TextElement textElement,
      int i,
      double? dx,
      double? dy,
      double? width,
      double? height) {
    final Rect tempBounds = renderer.imageRenderGlyphList[i].boundingRect;
    final Rect glyphBounds = Rect.fromLTWH(
        tempBounds.left, tempBounds.top, tempBounds.width, tempBounds.height);
    final TextGlyph textGlyph = TextGlyphHelper.initialize(
        renderer.imageRenderGlyphList[i].toUnicode,
        textElement.fontName,
        textElement.fontStyle,
        _calculateBounds(glyphBounds),
        textElement.fontSize,
        renderer.imageRenderGlyphList[i].isRotated);
    dx = renderer.imageRenderGlyphList[i].boundingRect.left;
    dy = renderer.imageRenderGlyphList[i].boundingRect.top;
    height = renderer.imageRenderGlyphList[i].boundingRect.height;
    if (dx > renderer.imageRenderGlyphList[i].boundingRect.left) {
      width = (dx - renderer.imageRenderGlyphList[i].boundingRect.left) +
          renderer.imageRenderGlyphList[i].boundingRect.width;
    } else {
      width = (renderer.imageRenderGlyphList[i].boundingRect.left - dx) +
          renderer.imageRenderGlyphList[i].boundingRect.width;
    }
    return <String, dynamic>{
      'word': TextWordHelper.initialize(
          ' ',
          textElement.fontName,
          textElement.fontStyle,
          <TextGlyph>[textGlyph],
          Rect.fromLTWH(dx, dy, width, height),
          textElement.fontSize),
      'dx': dx,
      'dy': dy,
      'width': width,
      'height': height
    };
  }

  Rect _calculatedTextounds(
      List<Glyph> glyphs, String text, int index, PdfPage page) {
    final Glyph startGlyph = glyphs[index];
    double x = startGlyph.boundingRect.left;
    double y = startGlyph.boundingRect.top;
    double width = 0;
    double height = startGlyph.boundingRect.height;
    //For conmplex script glyph mapping
    int endIndex = index + text.length - 1;
    int length = text.length;
    String tempString = '';
    for (int i = 0; i < text.length; i++) {
      tempString += glyphs[index + i].toUnicode;
      if (tempString == text) {
        endIndex = index + i;
        length = i + 1;
        break;
      }
    }
    final Glyph endGlyph = glyphs[endIndex];
    if (startGlyph.boundingRect.top == endGlyph.boundingRect.top ||
        (startGlyph.boundingRect.top - endGlyph.boundingRect.top).abs() <
            0.001) {
      if (x > endGlyph.boundingRect.left) {
        width = (x - endGlyph.boundingRect.left) + endGlyph.boundingRect.width;
        if (page.rotation == PdfPageRotateAngle.rotateAngle0 ||
            page.rotation == PdfPageRotateAngle.rotateAngle180) {
          width = startGlyph.boundingRect.height;
          for (int i = 0; i < length; i++) {
            height += glyphs[index + i].boundingRect.width;
            if (glyphs[index + i].boundingRect.height > width) {
              width = glyphs[index + i].boundingRect.height;
            }
          }
        } else {
          width = startGlyph.boundingRect.width;
          for (int i = 0; i < length; i++) {
            height += glyphs[index + i].boundingRect.height;
            if (glyphs[index + i].boundingRect.width > width) {
              width = glyphs[index + i].boundingRect.width;
            }
          }
        }
        x -= width;
      } else {
        width = (endGlyph.boundingRect.left - x) + endGlyph.boundingRect.width;
      }
    } else if (startGlyph.boundingRect.left == endGlyph.boundingRect.left ||
        (startGlyph.boundingRect.left - endGlyph.boundingRect.left).abs() <
            0.001) {
      if (startGlyph.boundingRect.top != endGlyph.boundingRect.top &&
          !((startGlyph.boundingRect.top - endGlyph.boundingRect.top).abs() <
              0.001)) {
        height = 0;
        if (page.rotation == PdfPageRotateAngle.rotateAngle0 ||
            page.rotation == PdfPageRotateAngle.rotateAngle180) {
          width = startGlyph.boundingRect.height;
          for (int i = 0; i < length; i++) {
            height += glyphs[index + i].boundingRect.width;
            if (glyphs[index + i].boundingRect.height > 0) {
              width = glyphs[index + i].boundingRect.height;
            }
          }
        } else {
          width = startGlyph.boundingRect.width;
          for (int i = 0; i < length; i++) {
            height += glyphs[index + i].boundingRect.height;
            width = glyphs[index + i].boundingRect.width;
          }
        }
        if (y > endGlyph.boundingRect.top || startGlyph.rotationAngle == 270) {
          x = startGlyph.boundingRect.left - width + 1;
          y = startGlyph.boundingRect.top - height;
        } else if (y < endGlyph.boundingRect.top ||
            startGlyph.rotationAngle == 90) {
          x = startGlyph.boundingRect.left - 1;
          y = startGlyph.boundingRect.top;
        }
      }
    }
    return _calculateBounds(Rect.fromLTWH(x, y, width, height));
  }

  bool _hasEscapeCharacter(String text) {
    return text.contains(' ') ||
        text.contains(r'\u0007') ||
        text.contains(r'\') ||
        text.contains(r'\b') ||
        text.contains(r'\f') ||
        text.contains(r'\r') ||
        text.contains(r'\t') ||
        text.contains(r'\n') ||
        text.contains(r'\v') ||
        text.contains(r"\'") ||
        text.contains(r'\u0000');
  }

  Rect _calculateBounds(Rect bounds) {
    if (_currentPage != null) {
      if (PdfPageHelper.getHelper(_currentPage!).cropBox != Rect.zero &&
          PdfPageHelper.getHelper(_currentPage!).cropBox !=
              PdfPageHelper.getHelper(_currentPage!).mediaBox) {
        final double x =
            bounds.left - PdfPageHelper.getHelper(_currentPage!).cropBox.left;
        final double y =
            bounds.top + PdfPageHelper.getHelper(_currentPage!).cropBox.top;
        return Rect.fromLTWH(x, y, bounds.width, bounds.height);
      }
    }
    return bounds;
  }

  TextLine _prepareTextLine(TextLine textLine, ImageRenderer renderer,
      int lineStartIndex, int glyphIndex, double rotation) {
    bool isSameFontName = true;
    bool isSameFontSize = true;
    bool isSameFontStyle = true;
    String? fontName = '';
    double? fontSize = 0;
    textLine.pageIndex = _currentPageIndex;
    List<PdfFontStyle>? fontStyle = <PdfFontStyle>[PdfFontStyle.regular];
    if (rotation == 270 &&
        renderer.imageRenderGlyphList[lineStartIndex].isRotated) {
      textLine.bounds = Rect.fromLTWH(
          renderer.imageRenderGlyphList[lineStartIndex].boundingRect.left,
          renderer.imageRenderGlyphList[lineStartIndex].boundingRect.top,
          renderer.imageRenderGlyphList[glyphIndex - 1].boundingRect.width,
          renderer.imageRenderGlyphList[glyphIndex - 1].boundingRect.bottom -
              renderer.imageRenderGlyphList[lineStartIndex].boundingRect.top);
    } else {
      textLine.bounds = Rect.fromLTWH(
          renderer.imageRenderGlyphList[lineStartIndex].boundingRect.left,
          renderer.imageRenderGlyphList[glyphIndex - 1].boundingRect.top,
          renderer.imageRenderGlyphList[glyphIndex - 1].boundingRect.right -
              renderer.imageRenderGlyphList[lineStartIndex].boundingRect.left,
          renderer.imageRenderGlyphList[glyphIndex - 1].boundingRect.height);
    }
    textLine.bounds = _calculateBounds(textLine.bounds);
    for (int i = lineStartIndex; i < glyphIndex; i++) {
      final Glyph glyph = renderer.imageRenderGlyphList[i];
      if (i == 0) {
        fontName = glyph.fontFamily;
        fontSize = glyph.fontSize;
        fontStyle = glyph.fontStyle;
      }
      textLine.text = textLine.text + glyph.toUnicode;
      if (fontName == glyph.fontFamily && isSameFontName) {
        textLine.fontName = fontName!;
      } else {
        isSameFontName = false;
        textLine.fontName = '';
      }
      if (fontSize == glyph.fontSize && isSameFontSize) {
        textLine.fontSize = fontSize!;
      } else {
        isSameFontSize = false;
        textLine.fontSize = 0;
      }

      if (fontStyle == glyph.fontStyle && isSameFontStyle) {
        textLine.fontStyle = fontStyle!;
      } else {
        isSameFontStyle = false;
        textLine.fontStyle = <PdfFontStyle>[PdfFontStyle.regular];
      }
      if (!isSameFontName) {
        isSameFontName = true;
      }
      if (!isSameFontSize) {
        isSameFontSize = true;
      }
      if (!isSameFontStyle) {
        isSameFontStyle = true;
      }
    }
    return textLine;
  }

  String _renderText(
      PdfRecordCollection? recordCollection, PdfPageResources pageResources) {
    String resultantText = '';
    if (recordCollection != null &&
        recordCollection.recordCollection.isNotEmpty) {
      final List<PdfRecord> records = recordCollection.recordCollection;
      for (int i = 0; i < records.length; i++) {
        final PdfRecord record = records[i];
        final String token = record.operatorName!;
        final List<String>? elements = record.operands;
        for (int j = 0; j < _symbolChars.length; j++) {
          if (token.contains(_symbolChars[j])) {
            token.replaceAll(_symbolChars[j], '');
          }
        }
        switch (token.trim()) {
          case 'T*':
            {
              resultantText += '\r\n';
              break;
            }
          case 'Tf':
            {
              _renderFont(elements!, pageResources);
              break;
            }
          case 'ET':
            {
              resultantText += '\r\n';
              break;
            }
          case 'Tj':
          case 'TJ':
          case "'":
            {
              final String? resultText =
                  _renderTextElement(elements!, token, pageResources);
              if (resultText != null) {
                resultantText += resultText;
              }
              if (token == "'") {
                resultantText += '\r\n';
              }
              break;
            }
          case 'Do':
            {
              final String? result =
                  _getXObject(resultantText, elements!, pageResources);
              if (result != null && result != '') {
                resultantText += result;
              }
              break;
            }
          default:
            break;
        }
      }
    }
    return resultantText;
  }

  String _renderTextAsLayout(
      PdfRecordCollection? recordCollection, PdfPageResources pageResources) {
    double? currentMatrixY = 0;
    double? prevMatrixY = 0;
    double? currentY = 0;
    double? prevY = 0;
    double differenceX = 0;
    String? currentText = '';
    bool hasTj = false;
    bool hasTm = false;
    _hasBDC = false;
    String resultantText = '';
    double? textLeading = 0;
    double? horizontalScaling = 100;
    bool hasNoSpacing = false;
    bool spaceBetweenWord = false;
    _tempBoundingRectangle = Rect.zero;
    if (recordCollection != null &&
        recordCollection.recordCollection.isNotEmpty) {
      final List<PdfRecord> records = recordCollection.recordCollection;
      for (int i = 0; i < records.length; i++) {
        final PdfRecord record = records[i];
        final String token = record.operatorName!;
        final List<String>? elements = record.operands;
        for (int j = 0; j < _symbolChars.length; j++) {
          if (token.contains(_symbolChars[j])) {
            token.replaceAll(_symbolChars[j], '');
          }
        }
        switch (token.trim()) {
          case 'Tw':
            {
              _wordSpacing = double.tryParse(elements![0])!;
              break;
            }
          case 'Tc':
            {
              _characterSpacing = double.tryParse(elements![0])!;
              break;
            }
          case 'Tm':
            {
              final double a = double.tryParse(elements![0])!;
              final double b = double.tryParse(elements[1])!;
              final double c = double.tryParse(elements[2])!;
              final double d = double.tryParse(elements[3])!;
              final double e = double.tryParse(elements[4])!;
              final double f = double.tryParse(elements[5])!;
              _textLineMatrix = MatrixHelper(a, b, c, d, e, f);
              _textMatrix = MatrixHelper(a, b, c, d, e, f);
              if (_textMatrix!.offsetY == _textLineMatrix!.offsetY &&
                  _textMatrix!.offsetX != _textLineMatrix!.offsetX) {
                _textLineMatrix = _textMatrix!.clone();
              }
              if (_textLineMatrix!.offsetY != _currentTextMatrix!.offsetY ||
                  ((_textLineMatrix!.offsetX != _currentTextMatrix!.offsetX) &&
                      _hasBDC &&
                      !hasTj)) {
                _tempBoundingRectangle = Rect.zero;
                _hasBDC = false;
              }
              break;
            }
          case 'TL':
            {
              textLeading = -double.tryParse(elements![0])!;
              break;
            }
          case 'cm':
            {
              currentMatrixY = double.tryParse(elements![5]);
              final int current = currentMatrixY!.toInt();
              final int prev = prevMatrixY!.toInt();
              final int locationY = (current - prev) ~/ 10;
              if ((current != prev) &&
                  hasTm &&
                  (locationY < 0 || locationY >= 1)) {
                resultantText += '\r\n';
                hasTm = false;
              }
              prevMatrixY = currentMatrixY;
              break;
            }
          case 'BDC':
            {
              _hasBDC = true;
              break;
            }
          case 'TD':
            {
              textLeading = double.tryParse(elements![1]);
              _textMatrix = MatrixHelper(
                      1,
                      0,
                      0,
                      1,
                      double.tryParse(elements[0])!,
                      double.tryParse(elements[1])!) *
                  _textLineMatrix!;
              _textLineMatrix = _textMatrix!.clone();
              if (_textLineMatrix!.offsetY != _currentTextMatrix!.offsetY ||
                  (_hasBDC &&
                      _textLineMatrix!.offsetX != _currentTextMatrix!.offsetX &&
                      !hasTj)) {
                _tempBoundingRectangle = Rect.zero;
                _hasBDC = false;
              }
              break;
            }
          case 'Td':
            {
              _textMatrix = MatrixHelper(
                      1,
                      0,
                      0,
                      1,
                      double.tryParse(elements![0])!,
                      double.tryParse(elements[1])!) *
                  _textLineMatrix!;
              _textLineMatrix = _textMatrix!.clone();
              if (_textLineMatrix!.offsetY != _currentTextMatrix!.offsetY ||
                  (_hasBDC &&
                      _textLineMatrix!.offsetX !=
                          _currentTextMatrix!.offsetX)) {
                _tempBoundingRectangle = Rect.zero;
                _hasBDC = false;
              }
              if ((_textLineMatrix!.offsetX - _currentTextMatrix!.offsetX) >
                      0 &&
                  !spaceBetweenWord &&
                  hasTj) {
                differenceX =
                    _textLineMatrix!.offsetX - _currentTextMatrix!.offsetX;
                spaceBetweenWord = true;
              }
              break;
            }
          case 'Tz':
            {
              horizontalScaling = double.tryParse(elements![0]);
              break;
            }
          case 'BT':
            {
              _textMatrix = MatrixHelper(0, 0, 0, 0, 0, 0);
              _textLineMatrix = MatrixHelper(0, 0, 0, 0, 0, 0);
              break;
            }
          case 'T*':
            {
              _textMatrix =
                  MatrixHelper(1, 0, 0, 1, 0, textLeading!) * _textLineMatrix!;
              _textLineMatrix = _textMatrix!.clone();
              break;
            }
          case 'Tf':
            {
              _renderFont(elements!, pageResources);
              break;
            }
          case 'ET':
            {
              final double endTextPosition =
                  (_textLineMatrix!.offsetX - _tempBoundingRectangle!.right) /
                      10;
              if (_hasLeading && endTextPosition == 0 && hasNoSpacing) {
                resultantText += ' ';
                _tempBoundingRectangle = Rect.zero;
                _hasLeading = false;
              }
              break;
            }
          case 'Tj':
          case 'TJ':
            {
              final String currentToken = token.trim();
              currentY = _textMatrix!.offsetY;
              double difference = 0;
              if (_fontSize! >= 10) {
                difference = ((currentY - prevY!) / 10).round().toDouble();
              } else {
                difference =
                    ((currentY - prevY!) / _fontSize!).round().toDouble();
              }
              if (difference < 0) {
                difference = -difference;
              }
              if (spaceBetweenWord) {
                if (differenceX > _fontSize!) {
                  differenceX = 0;
                }
                spaceBetweenWord = false;
              }
              hasTj = true;
              if (prevY != 0 && difference >= 1) {
                resultantText += '\r\n';
              }
              currentText = currentToken == 'TJ'
                  ? _renderTextElementTJ(
                      elements!, token, pageResources, horizontalScaling)
                  : _renderTextElement(elements!, token, pageResources);
              _currentTextMatrix = _textLineMatrix!.clone();
              prevY = currentY;
              resultantText += currentText!;
              _textMatrix = _textLineMatrix!.clone();
              if (currentToken == 'TJ') {
                _hasBDC = false;
              }
              break;
            }
          case "'":
            {
              currentY = _textMatrix!.offsetY;
              hasNoSpacing = false;
              double difference = 0;
              if (_fontSize! >= 10) {
                difference = ((currentY - prevY!) / 10).round().toDouble();
              } else {
                difference =
                    ((currentY - prevY!) / _fontSize!).round().toDouble();
              }
              if (difference < 0) {
                difference = -difference;
              }
              _hasLeading = true;
              if (prevY != 0 && difference >= 1) {
                resultantText += '\r\n';
              }
              prevY = currentY;
              final int currentXPosition =
                  _textLineMatrix!.offsetX.toInt().toSigned(64);
              final int prevXPosition =
                  _currentTextMatrix!.offsetX.toInt().toSigned(64);
              if ((prevXPosition - currentXPosition) > 0) {
                hasNoSpacing = true;
              }
              _textMatrix =
                  MatrixHelper(1, 0, 0, 1, 0, textLeading!) * _textLineMatrix!;
              _textLineMatrix = _textMatrix!.clone();
              currentText = _renderTextElement(elements!, token, pageResources);
              _currentTextMatrix = _textLineMatrix!.clone();
              resultantText += currentText!;
              break;
            }
          case 'Do':
            {
              final String? result =
                  _getXObject(resultantText, elements!, pageResources);
              if (result != null && result != '') {
                resultantText += result;
              }
              break;
            }
          default:
            break;
        }
      }
    }
    return resultantText;
  }

  String _skipEscapeSequence(String text) {
    int index = -1;
    do {
      index = text.indexOf(r'\', index + 1);
      if (text.length > index + 1) {
        final String nextLiteral = text[index + 1];
        if (index >= 0 &&
            (nextLiteral == r'\' || nextLiteral == '(' || nextLiteral == ')')) {
          text = text.replaceFirst(text[index], '', index);
        }
      } else {
        text = text.replaceFirst(text[index], '', index);
        index = -1;
      }
    } while (index >= 0);
    return text;
  }

  void _renderFont(List<String> elements, PdfPageResources resources) {
    int i = 0;
    for (i = 0; i < elements.length; i++) {
      if (elements[i].contains('/')) {
        _currentFont = elements[i].replaceAll('/', '');
        break;
      }
    }
    _fontSize = double.tryParse(elements[i + 1]);
    if (resources.containsKey(_currentFont)) {
      final FontStructure structure = resources[_currentFont!] as FontStructure;
      if (structure.isStandardFont) {
        structure.createStandardFont(_fontSize!);
      } else if (structure.isStandardCJKFont) {
        structure.createStandardCJKFont(_fontSize!);
      }
    }
  }

  String _renderTextElementTJ(List<String> elements, String tokenType,
      PdfPageResources pageResources, double? horizontalScaling) {
    List<String> decodedList = <String>[];
    final String text = elements.join();
    String tempText = '';
    if (pageResources.containsKey(_currentFont)) {
      FontStructure? fontStructure;
      final dynamic returnValue = pageResources[_currentFont!];
      if (returnValue != null && returnValue is FontStructure) {
        fontStructure = returnValue;
      }
      fontStructure!.isTextExtraction = true;
      fontStructure.fontSize = _fontSize;
      if (!fontStructure.isEmbedded &&
          fontStructure.isStandardCJKFont &&
          fontStructure.font != null) {
        decodedList = fontStructure.decodeCjkTextExtractionTJ(
            text, pageResources.isSameFont());
      } else {
        decodedList = fontStructure.decodeTextExtractionTJ(
            text, pageResources.isSameFont());
      }
      fontStructure.isTextExtraction = false;
      tempText =
          _renderTextFromTJ(decodedList, horizontalScaling, fontStructure);
    }
    return tempText;
  }

  String _renderTextFromTJ(List<String> decodedList, double? horizontalScaling,
      FontStructure? fontStructure) {
    String extractedText = '';
    for (String word in decodedList) {
      final double? space = double.tryParse(word);
      if (space != null) {
        _textLineMatrix =
            _updateTextMatrixWithSpacing(space, horizontalScaling!);
        if ((_textLineMatrix!.offsetX - _textMatrix!.offsetX).toInt() > 1 &&
            !_hasBDC) {
          extractedText += ' ';
        }
      } else {
        double _characterWidth = 1.0;
        if (word != '' && word[word.length - 1] == 's') {
          word = word.substring(0, word.length - 1);
        }
        for (int i = 0; i < word.length; i++) {
          final String renderedCharacter = word[i];
          MatrixHelper transform = MatrixHelper(1, 0, 0, 1, 0, 0);
          if (!fontStructure!.isEmbedded &&
              fontStructure.isStandardFont &&
              fontStructure.font != null) {
            final PdfStandardFont font = fontStructure.font! as PdfStandardFont;
            _characterWidth = PdfStandardFontHelper.getHelper(font)
                    .getCharWidthInternal(renderedCharacter) *
                PdfFontHelper.characterSizeMultiplier;
          } else if (!fontStructure.isEmbedded &&
              fontStructure.isStandardCJKFont &&
              fontStructure.font != null) {
            final PdfCjkStandardFont font =
                fontStructure.font! as PdfCjkStandardFont;
            _characterWidth = PdfCjkStandardFontHelper.getHelper(font)
                    .getCharWidthInternal(renderedCharacter) *
                PdfFontHelper.characterSizeMultiplier;
          } else {
            _characterWidth =
                _getCharacterWidth(renderedCharacter, fontStructure);
          }
          _textMatrix = _getTextRenderingMatrix(horizontalScaling!);
          final MatrixHelper identity = MatrixHelper.identity.clone();
          identity.scale(0.01, 0.01, 0.0, 0.0);
          identity.translate(0.0, 1.0);
          final MatrixHelper matrix = transform.clone();
          transform = matrix;
          double? tempFontSize;
          if (_textMatrix!.m11 > 0) {
            tempFontSize = _textMatrix!.m11;
          } else if (_textMatrix!.m12 != 0 && _textMatrix!.m21 != 0) {
            if (_textMatrix!.m12 < 0) {
              tempFontSize = -_textMatrix!.m12;
            } else {
              tempFontSize = _textMatrix!.m12;
            }
          } else {
            tempFontSize = _fontSize;
          }
          final Rect boundingRect = Rect.fromLTWH(
              matrix.offsetX / 1.3333333333333333,
              (matrix.offsetY - tempFontSize!) / 1.3333333333333333,
              _characterWidth * tempFontSize,
              tempFontSize);
          if (_tempBoundingRectangle != null) {
            final double boundingDifference =
                ((boundingRect.left - _tempBoundingRectangle!.right) / 10)
                    .round()
                    .toDouble();
            if ((_tempBoundingRectangle!.right != 0 &&
                    boundingRect.left != 0) &&
                boundingDifference >= 1 &&
                _hasLeading) {
              extractedText += ' ';
            }
          }
          extractedText += renderedCharacter;
          _textLineMatrix =
              _updateTextMatrix(_characterWidth, horizontalScaling);
          _tempBoundingRectangle = boundingRect;
          _textMatrix = _textLineMatrix!.clone();
        }
      }
    }
    return extractedText;
  }

  String? _renderTextElement(
      List<String> elements, String tokenType, PdfPageResources pageResources) {
    try {
      String text = elements.join();
      if (!pageResources.containsKey(_currentFont)) {
        if (_currentFont != null && _currentFont!.contains('-')) {
          _currentFont = _currentFont!.replaceAll('-', '#2D');
        }
      }
      if (pageResources.containsKey(_currentFont)) {
        FontStructure? fontStructure;
        final dynamic returnValue = pageResources[_currentFont!];
        if (returnValue != null && returnValue is FontStructure) {
          fontStructure = returnValue;
        }
        fontStructure!.isTextExtraction = true;
        fontStructure.fontSize = _fontSize;
        text = fontStructure.decodeTextExtraction(text, true);
        fontStructure.isTextExtraction = false;
      }
      return text;
    } catch (e) {
      return null;
    }
  }

  String? _getXObject(String resultantText, List<String> xobjectElement,
      PdfPageResources pageResources) {
    String? result;
    final String key = xobjectElement[0].replaceAll('/', '');
    if (pageResources.containsKey(key)) {
      final dynamic element = pageResources[key];
      if (element is XObjectElement) {
        final PdfRecordCollection collection = element.render(pageResources)!;
        final PdfDictionary xobjects = element.dictionary!;
        PdfPageResources childResource = PdfPageResources();
        if (xobjects.containsKey(PdfDictionaryProperties.resources)) {
          PdfDictionary? pageDictionary = PdfDictionary();
          final IPdfPrimitive? resource =
              xobjects[PdfDictionaryProperties.resources];
          if (resource is PdfReferenceHolder &&
              resource.object is PdfDictionary) {
            pageDictionary = resource.object as PdfDictionary?;
          } else if (resource is PdfDictionary) {
            pageDictionary = resource;
          }
          childResource = _resourceLoader.updatePageResources(
              childResource, _resourceLoader.getFormResources(pageDictionary));
          childResource = _resourceLoader.updatePageResources(childResource,
              _resourceLoader.getFontResources(pageDictionary, _currentPage));
        } else {
          childResource = _updateFontResources(pageResources);
        }
        if (_isLayout) {
          result = '${_renderTextAsLayout(collection, childResource)}\r\n';
        } else {
          result = _renderText(collection, childResource);
        }
        collection.recordCollection.clear();
      }
    }
    return result;
  }

  PdfPageResources _updateFontResources(PdfPageResources pageResources) {
    final PdfPageResources resources = PdfPageResources();
    pageResources.resources.forEach((String? key, dynamic value) {
      if (value is FontStructure) {
        resources.resources[key] = value;
        resources.fontCollection[key] = value;
      }
    });
    return resources;
  }

  MatrixHelper? _updateTextMatrixWithSpacing(
      double space, double horizontalScaling) {
    final double x = -(space * 0.001 * _fontSize! * horizontalScaling / 100);
    final Offset point = _textLineMatrix!.transform(Offset.zero);
    final Offset point2 = _textLineMatrix!.transform(Offset(x, 0.0));
    if (point.dx != point2.dx) {
      _textLineMatrix!.offsetX = point2.dx;
    } else {
      _textLineMatrix!.offsetY = point2.dy;
    }
    return _textLineMatrix;
  }

  MatrixHelper _getTextRenderingMatrix(double textHorizontalScaling) {
    return MatrixHelper(_fontSize! * (textHorizontalScaling / 100), 0, 0,
            -_fontSize!, 0, _fontSize!) *
        _textLineMatrix! *
        _currentTransformationMatrix;
  }

  double _getCharacterWidth(String character, FontStructure structure) {
    final int _charID = character.codeUnitAt(0);
    return (structure.fontGlyphWidths != null &&
            structure.fontType!.name == 'TrueType' &&
            structure.fontGlyphWidths!.containsKey(_charID))
        ? structure.fontGlyphWidths![_charID]! * 0.001
        : 1.0;
  }

  MatrixHelper _updateTextMatrix(
      double characterWidth, double horizontalScaling) {
    final double offsetX =
        (characterWidth * _fontSize! + _characterSpacing + _wordSpacing) *
            (horizontalScaling / 100);
    return MatrixHelper(1.0, 0.0, 0.0, 1.0, offsetX, 0.0) * _textLineMatrix!;
  }

  double _getPageRotation(PdfPage page) {
    if (page.rotation == PdfPageRotateAngle.rotateAngle90) {
      return 90;
    } else if (page.rotation == PdfPageRotateAngle.rotateAngle180) {
      return 180;
    } else if (page.rotation == PdfPageRotateAngle.rotateAngle270) {
      return 270;
    } else {
      return 0;
    }
  }
}
