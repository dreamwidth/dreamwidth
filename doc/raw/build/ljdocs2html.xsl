<?xml version="1.0" encoding="iso-8859-1"?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
                        xmlns:date="http://exslt.org/dates-and-times"
                        exclude-result-prefixes="date"
                        version="1.0">

<xsl:import href="xsl-docbook/html/chunkfast.xsl"/>

<!-- canonical URL support -->
<xsl:param name="use.id.as.filename" select="1"/>

<!-- More inline with perl style docs -->
<xsl:param name="funcsynopsis.style">ansi-nontabular</xsl:param>

<!-- Label sections -->
<xsl:param name="section.autolabel" select="1"/>

<xsl:param name="local.l10n.xml" select="document('')"/>

<xsl:param name="toc.section.depth">2</xsl:param>

<xsl:param name="chunk.section.depth" select="1"/>

<xsl:param name="chunk.first.sections" select="1"/>

<xsl:param name="chunker.output.indent" select="'yes'"></xsl:param>

<xsl:param name="generate.id.attributes" select="1"></xsl:param>

<xsl:param name="chunker.output.doctype-public">-//W3C//DTD HTML 4.01 Transitional//EN</xsl:param>
<xsl:param name="chunker.output.doctype-system">http://www.w3.org/TR/html4/loose.dtd</xsl:param>

<xsl:param name="make.valid.html" select="1"></xsl:param>

<xsl:param name="html.cleanup" select="1"></xsl:param>

<xsl:param name="refentry.generate.title" select="1"/>

<xsl:param name="refentry.generate.name" select="0"/>

<xsl:param name="editedby.enabled">0</xsl:param>

<xsl:param name="glossary.sort" select="1"></xsl:param>
<xsl:param name="glossentry.show.acronym">primary</xsl:param>

<xsl:param name="qanda.defaultlabel">number</xsl:param>
<xsl:param name="qandadiv.autolabel" select="0"></xsl:param>
<xsl:param name="qanda.inherit.numeration" select="0"></xsl:param>

<xsl:template name="body.attributes"></xsl:template>

<xsl:template match="ulink" name="ulink">
  <xsl:variable name="link">
    <a>
      <xsl:if test="@id">
        <xsl:attribute name="name">
          <xsl:value-of select="@id"/>
        </xsl:attribute>
      </xsl:if>
      <xsl:attribute name="href"><xsl:value-of select="@url"/></xsl:attribute>
      <xsl:if test="$ulink.target != ''">
        <xsl:attribute name="target">
          <xsl:value-of select="$ulink.target"/>
        </xsl:attribute>
      </xsl:if>
      <xsl:choose>
        <xsl:when test="count(child::node())=0">
          <xsl:value-of select="@url"/>
        </xsl:when>
        <xsl:otherwise>
          <xsl:apply-templates/>
        </xsl:otherwise>
      </xsl:choose>
      <span class="ulink"> <img src="/img/link.png" alt="[o]" title="" /></span>
    </a>
  </xsl:variable>
  <xsl:copy-of select="$link"/>
</xsl:template>

<xsl:template match="chapter[@status = 'prelim']" mode="class.value">
  <xsl:value-of select="'draft-chapter'"/>
</xsl:template>

<xsl:param name="callout.graphics.path">/img/docs/callouts/</xsl:param>
<xsl:param name="img.src.path">/img/docs/</xsl:param>

<xsl:template match="authorgroup" mode="titlepage.mode">
  <div class="{name(.)}">
    <h3 class="authors">Authors</h3>
    <xsl:apply-templates mode="titlepage.mode"/>
  </div>
</xsl:template>

<xsl:template match="author" mode="titlepage.mode">
    <xsl:call-template name="authors.div"/>
</xsl:template>

<xsl:template name="authors.div">
    <div>
        <xsl:apply-templates select="." mode="class.attribute"/>
        <xsl:if test="self::editor[position()=1] and not($editedby.enabled = 0)">
        <h4 class="editedby"><xsl:call-template name="gentext.edited.by"/></h4>
        </xsl:if>
        <strong>
        <xsl:apply-templates select="." mode="class.attribute"/>
        <xsl:call-template name="person.name"/></strong>&#xA0;
        <tt><xsl:apply-templates mode="titlepage.mode" select="email"/></tt>
        
        <xsl:if test="not($contrib.inline.enabled = 0)">
            <xsl:apply-templates mode="titlepage.mode" select="contrib"/>
        </xsl:if>
        <xsl:if test="not($blurb.on.titlepage.enabled = 0)">
            <xsl:choose>
            <xsl:when test="$contrib.inline.enabled = 0">
            <xsl:apply-templates mode="titlepage.mode"
                    select="contrib|authorblurb|personblurb"/>
            </xsl:when>
            <xsl:otherwise>
            <xsl:apply-templates mode="titlepage.mode"
                    select="authorblurb|personblurb"/>
            </xsl:otherwise>
            </xsl:choose>
        </xsl:if>
    </div>
</xsl:template>

<xsl:template match="editor" mode="titlepage.mode">
    <xsl:call-template name="editors.div"/>
</xsl:template>

<xsl:template name="editors.div">
    <div>
        <xsl:apply-templates select="." mode="class.attribute"/>
        <xsl:if test="self::editor[position()=1] and not($editedby.enabled = 0)">
        <h4 class="editedby"><xsl:call-template name="gentext.edited.by"/></h4>
        </xsl:if>
        <strong>
        <xsl:apply-templates select="." mode="class.attribute"/>Editor:
        <xsl:call-template name="person.name"/></strong>&#xA0;
        <tt><xsl:apply-templates mode="titlepage.mode" select="email"/></tt>
        
        <xsl:if test="not($contrib.inline.enabled = 0)">
        <xsl:apply-templates mode="titlepage.mode" select="contrib"/>
        </xsl:if>
        <xsl:if test="not($blurb.on.titlepage.enabled = 0)">
            <xsl:choose>
            <xsl:when test="$contrib.inline.enabled = 0">
            <xsl:apply-templates mode="titlepage.mode"
                    select="contrib|authorblurb|personblurb"/>
            </xsl:when>
            <xsl:otherwise>
            <xsl:apply-templates mode="titlepage.mode"
                    select="authorblurb|personblurb"/>
            </xsl:otherwise>
            </xsl:choose>
        </xsl:if>
    </div>
</xsl:template>

<xsl:template name="user.head.content">
  <meta name="date">
    <xsl:attribute name="content">
      <xsl:call-template name="datetime.format">
        <xsl:with-param name="date" select="date:date-time()"/>
        <xsl:with-param name="format" select="'Y-b-d'" padding="0"/>
      </xsl:call-template>
    </xsl:attribute>
  </meta>
</xsl:template>

<l:i18n xmlns:l="http://docbook.sourceforge.net/xmlns/l10n/1.0">
  <l:l10n language="en">
    <l:context name="xref">
      <l:template name="chapter" text="Chapter %n: %t"/>
    </l:context>
    <l:context name="section-xref-numbered">
      <l:template name="section" text="Section %n: %t"/>
    </l:context>
  </l:l10n>
</l:i18n> 

</xsl:stylesheet>

