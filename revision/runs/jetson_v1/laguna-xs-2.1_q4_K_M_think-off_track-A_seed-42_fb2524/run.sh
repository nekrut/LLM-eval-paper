#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES="M117-bl M117-ch M117C1-bl M117C1-ch"

mkdir -p results

# Reference indexing (once)
if [ ! -f data/ref/chrM.fa.fai ]; then
    samtools faidx data/ref/chrM.fa
fi

for ext in amb ann bwt pac sa; do
    if [ ! -f "data/ref/chrM.fa.$ext" ]; then
        bwa index data/ref/chrM.fa
        break
    fi
done

# Per-sample processing
for sample in $SAMPLES; do
    bam=results/${sample}.bam
    bai=results/${sample}.bam.bai
    vcf_gz=results/${sample}.vcf.gz
    vcf_tbi=results/${sample}.vcf.gz.tbi

    # Check if all outputs exist and are up-to-date
    fq1=data/raw/${sample}_1.fq.gz
    fq2=data/raw/${sample}_2.fq.gz

    need_run=false
    if [ ! -f "$bam" ] || [ ! -f "$bai" ]; then
        need_run=true
    elif [ ! -f "$vcf_gz" ] || [ ! -f "$vcf_tbi" ]; then
        need_run=true
    else
        # Check timestamps against inputs
        if [ "$fq1" -nt "$bam" ] || [ "$fq2" -nt "$bam" ]; then
            need_run=true
        elif [ "$bam" -nt "$vcf_gz" ]; then
            need_run=true
        fi
    fi

    if [ "$need_run" = true ]; then
        # Alignment with bwa mem, pipe to samtools sort
        bwa mem -t $THREADS -R "@RG	ID:${sample}	SM:${sample}	LB:${sample}	PL:ILLUMINA" \
            data/ref/chrM.fa "${fq1}" "${fq2}" | \
            samtools sort -@ $THREADS -o "$bam"

        # BAM indexing
        samtools index -@ $THREADS "$bam"

        # Variant calling with lofreq call-parallel
        tmp_vcf=results/${sample}.vcf
        lofq ref=data/ref/chrM.fa -f "$bam" --pp-threads $THREADS > "$tmp_vcf"

        # VCF compression and indexing
        bgzip -c "$tmp_vcf" > "$vcf_gz"
        tabix -p vcf "$vcf_gz"
        rm -f "$tmp_vcf"
    fi
done

# Collapsed TSV generation
collapsed=results/collapsed.tsv
need_collapse=false

if [ ! -f "$collapsed" ]; then
    need_collapse=true
else
    for sample in $SAMPLES; do
        vcf_gz=results/${sample}.vcf.gz
        if [ "$vcf_gz" -nt "$collapsed" ]; then
            need_collapse=true
            break
        fi
    done
fi

if [ "$need_collapse" = true ]; then
    echo -e "sample\tchrom\tpos\tref\talt\taf" > "$collapsed"
    for sample in $SAMPLES; do
        bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' \
            results/${sample}.vcf.gz >> "$collapsed"
    done
fi

exit 0