<?xml version="1.0"?>

<!-- LiveJournal XSLT stylesheet created by Tribeless Nomad (AJW) -->
<!-- converts DB schema documentation from custom XML to DocBook XML -->
<!-- The source document should comply with dbschema.dtd version 1.0.5. -->

<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">
<xsl:output method="xml" omit-xml-declaration="yes" indent="yes" />

  <xsl:template match="/">

    <xsl:for-each select="dbschema/dbtbl">
      <refentry><xsl:attribute name="id"><xsl:text>ljp.dbschema.</xsl:text><xsl:value-of select="@id"/></xsl:attribute>
      <refnamediv>
      <refname><database class="table"><xsl:value-of select="name"/></database></refname>
      <refpurpose><xsl:apply-templates select="description/node()"/></refpurpose>
      </refnamediv>
      <refsect1>
        <title><database class="table"><xsl:value-of select="name"/></database></title>
      <informaltable><tgroup cols="5">
      <thead>
      <row>
      <entry>Column name</entry>
      <entry>Type</entry>
      <entry>Null</entry>
      <entry>Default</entry>
      <entry>Description</entry>
      </row>
      </thead>
      <tbody>
      <xsl:for-each select="dbcol">
        <row>
        <entry><database class="field"><xsl:value-of select="name"/></database></entry>
        <entry><type><xsl:value-of select="@type"/></type></entry>
        <entry align="center"><xsl:if test="@required[.='false']">YES</xsl:if></entry>
        <entry align="center"><xsl:if test="@default"><literal role="value"><xsl:value-of select="@default"/></literal></xsl:if></entry>
        <entry><xsl:apply-templates select="description/node()"/></entry>
        </row>
      </xsl:for-each>
      </tbody>
      </tgroup></informaltable>
      <xsl:choose>
        <xsl:when test="dbkey">
          <informaltable><tgroup cols="3">
          <thead>
          <row>
          <entry>Key name</entry>
          <entry>Type</entry>
          <entry>Column(s)</entry>
          </row>
          </thead>
          <tbody>
          <xsl:for-each select="dbkey">
            <row>
            <entry>
            <database class="key1"><xsl:value-of select="@name"/></database>
            </entry>
            <entry>
            <type><xsl:value-of select="@type"/></type>
            </entry>
            <entry>
            <xsl:for-each select="@colids">
              <database class="field"><xsl:value-of select="name"/></database>

              <xsl:if test="position() != last()">, </xsl:if>
            </xsl:for-each>
            </entry>
            </row>
          </xsl:for-each>
          </tbody>
          </tgroup></informaltable>
        </xsl:when>
        <xsl:otherwise>
          <para>No keys defined.</para>
        </xsl:otherwise>
      </xsl:choose>
      </refsect1>
      </refentry>
    </xsl:for-each>
  </xsl:template>
  <xsl:template match="dbtblref"><link><xsl:attribute name="linkend"><xsl:text>ljp.dbschema.</xsl:text><xsl:value-of select="@tblid"/></xsl:attribute><database class="table"><xsl:value-of select="."/></database></link></xsl:template>
  <xsl:template match="dbcolref"><database class="field"><xsl:value-of select="."/></database></xsl:template>

  <!-- I don't think the following template should be necessary, but in IE5 it is: -->
  <xsl:template match="text()"><xsl:value-of select="."/></xsl:template>

</xsl:stylesheet>