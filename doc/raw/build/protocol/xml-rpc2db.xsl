<?xml version="1.0"?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">

<xsl:output method="xml" omit-xml-declaration="yes" indent="yes" />

<xsl:template match="/"><xsl:apply-templates/></xsl:template>
<xsl:template match="ljxmlrpc"><xsl:apply-templates/></xsl:template>

<xsl:template match="method">
  <refentry><xsl:attribute name="id"><xsl:text>ljp.csp.xml-rpc.</xsl:text><xsl:value-of select="@name"/></xsl:attribute>
    <refnamediv>
      <refname><xsl:value-of select="@name"/></refname>
      <refpurpose><xsl:value-of select="shortdes"/></refpurpose>
    </refnamediv>

    <refsect1>
      <title>Mode Description</title>
      <para>
        <xsl:value-of select="des"/>
      </para>
    </refsect1>

    <refsect1>
      <title>Arguments</title>
      <orderedlist>
      <xsl:for-each select="arguments">
        <xsl:apply-templates/>
      </xsl:for-each>
      </orderedlist>

      <example><xsl:attribute name="id"><xsl:text>example-ljp.csp.xml-rpc-call_</xsl:text><xsl:value-of select="@name"/></xsl:attribute>
        <title>Sample call to <literal>LJ.XMLRPC.<xsl:value-of select="@name"/></literal></title>
        <para><programlisting>
          <xsl:value-of select="expost"/>
        </programlisting></para>
      </example>

    </refsect1>

    <refsect1>
      <title>Return Values</title>
      <orderedlist>
      <xsl:for-each select="returns">
        <xsl:apply-templates/>
      </xsl:for-each>
      </orderedlist>

      <example><xsl:attribute name="id"><xsl:text>example-ljp.csp.xml-rpc-return_</xsl:text><xsl:value-of select="@name"/></xsl:attribute>
        <title>Sample return value for <literal>LJ.XMLRPC.<xsl:value-of select="@name"/></literal></title>
        <para><programlisting>
          <xsl:value-of select="exreturn"/>
        </programlisting></para>
      </example>

    </refsect1>

  </refentry>
</xsl:template>

<xsl:template match="deslink">
  <xref><xsl:attribute name="linkend"><xsl:value-of select="@id"/></xsl:attribute></xref>
</xsl:template>

<xsl:template match="struct">
  <listitem><para>
  <emphasis>[struct]</emphasis>
  <xsl:call-template name="count"/>
  <xsl:for-each select="des">
     <xsl:apply-templates select="."/>
  </xsl:for-each>
  </para><para>
  Containing keys:
    <itemizedlist>
    <xsl:for-each select="*">
      <xsl:apply-templates select="."/>
    </xsl:for-each>
    </itemizedlist>
  </para></listitem>
</xsl:template>

<xsl:template match="scalar">
  <listitem><para>
  <emphasis>[scalar]</emphasis>
  <xsl:call-template name="count"/>
  <xsl:for-each select="*">
    <xsl:apply-templates select="."/>
  </xsl:for-each>
  </para></listitem>
</xsl:template>

<xsl:template match="key">
  <listitem><para>
  <emphasis role="strong"><xsl:value-of select="@name"/></emphasis>
    <xsl:call-template name="count"/>:    
    <xsl:for-each select="des">
      <xsl:apply-templates select="."/>
    </xsl:for-each>
    <itemizedlist>
    <xsl:for-each select="*">
      <xsl:apply-templates select="."/>
    </xsl:for-each>
    </itemizedlist>
  </para></listitem>
</xsl:template>

<xsl:template match="list">
  <listitem><para>
  <emphasis>[array]</emphasis> 
  <xsl:call-template name="count"/>
    <xsl:value-of select="des"/>
    Containing items:
    <itemizedlist>
    <xsl:for-each select="scalar|struct|list">
      <xsl:apply-templates select="."/>
    </xsl:for-each>
    </itemizedlist>
  </para></listitem>
</xsl:template>

<xsl:template name="count">
  <xsl:choose>
    <xsl:when test="@count='1'">(required)</xsl:when>
    <xsl:when test="@count='opt'">(optional)</xsl:when>
    <xsl:when test="@count='1more'">(required; multiple allowed)</xsl:when>
    <xsl:when test="@count='0more'">(optional; multiple allowed)</xsl:when>
  </xsl:choose>
</xsl:template>

</xsl:stylesheet>
